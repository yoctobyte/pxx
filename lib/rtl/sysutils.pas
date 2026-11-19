{ SPDX-License-Identifier: Zlib }
unit sysutils;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Canonical SysUtils-style helpers. Now that the compiler loads a real
  lib/rtl/sysutils on `uses sysutils` (bug-sysutils-unit-hard-skipped fixed,
  v10), the conversion helpers live here -- their FPC-correct home -- rather than
  the interim lib/rtl/strutils. Pure Pascal, FPC-compatible names. Track B. }

interface

{ ExceptionBase, the root BOTH exception trees descend from. It lives in
  compiler/builtin because pylib cannot reach lib/rtl, and pylib needs it too:
  a NilPy `except Exception:` binds the shared root, which is what lets one arm
  catch an RTL raise without the frontend bridging two unrelated hierarchies.
  See feature-a-one-exception-class-in-a-shared-unit. }
uses exceptions;

type
  { FPC's SysUtils character set — the parameter type of the CharInSet / character
    classification family, and what real code writes for `set of char` work
    (`cset: TSysCharSet; Include(cset, c)`). It was simply missing, so any unit using it
    failed to compile with "unknown type" (tset4). }
  TSysCharSet = set of AnsiChar;

  { FPC/Delphi declare this pair in SYSTEM, so real code reaches it with no uses
    clause -- RemObjects Pascal Script's uPSCompiler writes `Set_Union(Dest, Src:
    PByteArray; ByteSize: Integer)` and got "unknown type: PByteArray".
    Same reasoning as HModule below: pxx has no System unit, so implicitly
    reached System types live here.

    NAME COLLISION, DELIBERATE AND CHECKED: lib/rtl/hashing.pas declares its own
    `TByteArray = array of Byte` -- a DYNAMIC array, a different type wearing the
    same name. That is legal and normal in FPC too (a unit's own declaration
    shadows System's), and `uses sysutils, hashing` resolves to hashing's, which
    is what every existing caller already means. The static one is only ever
    reached through PByteArray. }
  TByteArray = array[0..32767] of Byte;
  PByteArray = ^TByteArray;

  { FPC declares `HModule` in SYSTEM, so it is visible with no uses clause at
    all — verified: a program with an empty uses clause compiles `var h: HModule`
    under FPC. pxx has no System unit, so code that reaches it implicitly has
    nowhere to find it, and `dynlibs` declaring it (as it does) is not enough:
    units do not re-export their imports transitively, so Synapse's
    `ssl_openssl3_lib.pas` — which gets there via `synafpc` -> `dynlibs` — fails
    with `unknown type: HModule` at its LoadLib/GetProcAddr helpers.

    Declared independently of dynlibs.TLibHandle rather than aliased through it,
    which is exactly what FPC does: System.HModule and DynLibs.TLibHandle are
    separate declarations of the same width, and both are PtrInt here, so the
    two spellings stay assignable. Aliasing instead would drag `dynlibs` (and
    `platform` behind it) into every single unit that uses SysUtils, for a type
    most of them never name. }
  HModule = PtrInt;

  TFileInfo = record
    Name: AnsiString;
    IsDir: Boolean;
    Size: Int64;
    ModifiedTime: Int64;
  end;
  TFileInfoArray = array of TFileInfo;

  { FPC's SysUtils string-vector and parameterless-procedure names. Both stop a
    program at its `var` line rather than at a call, so their absence reads as
    much worse than "one missing routine": nothing in the unit compiles.

    TStringArray is the result type of SplitString and of the TStringHelper
    Split family; declaring it here (not in `types`) is where FPC puts it. It is
    deliberately a distinct name from TStringDynArray, which FPC also has — the
    two are assignment-compatible, so code written against either works. }
  TStringArray = array of AnsiString;
  TStringDynArray = array of AnsiString;

  { FPC's generic dynamic-array alias. Real code NEVER declares this itself
    unless it is guarding for a version that lacked it:

      {$ifdef VER3_0_0}
      TArray<T> = array of T;
      {$endif}

    which is the correct idiom, because FPC has supplied it from 3.0.2 on. pxx
    answers VER3 / VER3_2 / VER3_2_2 (compiler/lexer.inc), so that guard is
    correctly SKIPPED — and before this line there was nothing to skip to, which
    is the whole of bug-b-rtl-provides-no-tarray-generic-but-pxx-claims-ver3-2-2:
    we claimed the version whose RTL provides the type and did not provide it.
    Generics.Collections died at `unknown type: TArray` on
    `function ToArrayImpl(ACount: SizeInt): TArray<T>`.

    HERE IS NOT WHERE FPC PUTS IT — FPC declares it in the SYSTEM unit, so it is
    ambient and visible with no `uses` at all. pxx has no lib/rtl/system.pas;
    its ambient types are compiler-side, which would make that a Track A change.
    SysUtils is the closest reachable place to put it, and the residual gap is
    exact: a unit naming TArray<T> WITHOUT `uses SysUtils` compiles under FPC
    and not here.

    THE "IT COVERS EVERY REAL CONSUMER" CLAIM THAT USED TO STAND HERE WAS
    MEASURED AND IS WRONG, and the way it is wrong is worth more than the fact.
    It rested on "all seven files in the rtl-generics corpus that name TArray<>
    also use SysUtils, checked rather than assumed" — which is TRUE, and was
    checked. Re-measured 2026-09-06 against the OTHER corpus: of the six
    fpc-testsuite files naming TArray<>, **ZERO** use SysUtils (trtti12,
    trtti16, tarray12, tarray18, tarrconstr5, ttbitconverter). Not a shortfall
    in the check — an inversion between two populations, 7/7 against 0/6, and
    the sentence generalised from the one it had.

    The reason the two corpora differ is structural rather than accidental:
    rtl-generics code uses generic COLLECTIONS, which need SysUtils for other
    reasons, so TArray arrives free. Testsuite files exercise TArray ITSELF and
    deliberately carry no more `uses` than the feature requires — so they are
    exactly the population that cannot get it here, and they are the population
    a conformance run is made of.

    Fixing it properly means an AMBIENT TArray, which is compiler-side and
    therefore Track A:
    bug-a-tarray-is-not-ambient-so-a-unit-that-names-it-without-uses-sysutils-is-refused }
  TArray<T> = array of T;

  { `type TProc0 = procedure;` is a one-line workaround, but every FPC example
    that takes a callback writes TProcedure, so the workaround is one the caller
    has to know to apply. }
  TProcedure = procedure;

  { FPC's float layout selector — the first argument of the FOUR-argument
    FloatToStrF, which is the only spelling real FPC code uses. }
  TFloatFormat = (ffGeneral, ffExponent, ffFixed, ffNumber, ffCurrency);

  TReplaceFlag  = (rfReplaceAll, rfIgnoreCase);
  TReplaceFlags = set of TReplaceFlag;

  { Delphi's TStringHelper surface — method-style string access
    (feature-p-delphi-string-helpers). FPC compiles this under
    {$modeswitch typehelpers}; it is the default style in anything written to
    Delphi 2009+ conventions, so a program using it is the normal case rather
    than an exotic one.

    INDEXING IS 0-BASED, which is Delphi's convention and NOT Pascal's. So
    `s.Substring(2)` drops two characters where `Copy(s, 2, n)` keeps from the
    second, and `s.IndexOf` answers one less than `Pos`. Getting that backwards
    is a silent wrong answer, so every value below was taken from fpc 3.2.2
    under {$modeswitch typehelpers} rather than derived:

      'Hello World'.Substring(2)     = 'llo World'    (not 'ello World')
      'Hello World'.IndexOf('o')     = 4              (Pos says 5)
      'a-b-a'.IndexOf('zz')          = -1             (Pos says 0)
      'abc'.Substring(9)             = ''             out of range, not an error
      'abc'.Substring(-1)            = 'abc'          negative clamps to 0
      'abc'.Substring(1, 99)         = 'bc'           count clamps to the tail
      'abc'.PadLeft(2)               = 'abc'          never truncates
      'a-b-a'.Replace('a', 'X')      = 'X-b-X'        replaces ALL by default
      ''.Split([','])                = one element    not zero

    `Length` is declared as a PROPERTY because that is how FPC declares it, and
    it does NOT work yet: pxx does not dispatch a property through a type
    helper, only a method — [[bug-p-a-type-helper-cannot-declare-a-property]].
    Every other member here works today. The declaration stays platonic rather
    than being respelled as a method, per CLAUDE.md's no-compiler-appeasement
    rule; it starts working when that bug is fixed, with no change here. }
  TStringHelper = type helper for AnsiString
  private
    { private because FPC declares it private -- `s.GetLength` is an
      `Illegal qualifier` there, so exposing it here would be a divergence
      invented to work around the property gap. }
    function GetLength: SizeInt;
  public
    property Length: SizeInt read GetLength;
    function IsEmpty: Boolean;
    function ToUpper: AnsiString;
    function ToLower: AnsiString;
    function Trim: AnsiString;
    function TrimLeft: AnsiString;
    function TrimRight: AnsiString;
    function Substring(AStartIndex: SizeInt): AnsiString; overload;
    function Substring(AStartIndex: SizeInt; ALen: SizeInt): AnsiString; overload;
    function IndexOf(const AValue: AnsiString): SizeInt; overload;
    function IndexOf(const AValue: AnsiString; StartIndex: SizeInt): SizeInt; overload;
    function LastIndexOf(const AValue: AnsiString): SizeInt;
    function StartsWith(const AValue: AnsiString): Boolean;
    function EndsWith(const AValue: AnsiString): Boolean;
    function Contains(const AValue: AnsiString): Boolean;
    function Replace(const OldValue, NewValue: AnsiString): AnsiString; overload;
    function Replace(const OldValue, NewValue: AnsiString; Flags: TReplaceFlags): AnsiString; overload;
    function Split(const Separators: array of Char): TStringArray;
    function PadLeft(ATotalWidth: SizeInt): AnsiString; overload;
    function PadLeft(ATotalWidth: SizeInt; PaddingChar: Char): AnsiString; overload;
    function PadRight(ATotalWidth: SizeInt): AnsiString; overload;
    function PadRight(ATotalWidth: SizeInt; PaddingChar: Char): AnsiString; overload;
  end;

  { FPC SysUtils event-log severity (eventlog.pp et al). }
  TEventType  = (etCustom, etInfo, etWarning, etError, etDebug);
  TEventTypes = set of TEventType;

  PInt64Rec  = ^Int64;
  PQWordRec  = ^QWord;   { the same boxed slot read UNSIGNED, for vtQWord }
  PDoubleRec = ^Double;

  { Days (integer part) since 1899-12-30, with the time-of-day as the
    fractional part — the standard FPC/Delphi representation. }
  TDateTime = Double;

  { FPC TTimeStamp: Time = milliseconds since midnight, Date = days since
    0001-01-01 (Trunc(dt) + DateDelta). }
  TTimeStamp = record
    Time: Integer;
    Date: Integer;
  end;

  { FPC SysUtils.TSystemTime -- a broken-down wall-clock time.

    THE TWO ARMS ARE ONE STORAGE, DELIBERATELY. FPC declares this as a variant
    record so the same eight words can be read under the plain names or under
    the `w`-prefixed Win32 names (`SYSTEMTIME` in the Windows API has the
    latter), and real source uses both spellings interchangeably. Copying the
    shape rather than picking one arm is what keeps `st.Year` and `st.wYear`
    the same field; a two-record version would compile every program and
    silently give one of them zeros.

    DayOfWeek IS 0-BASED HERE AND SysUtils.DayOfWeek IS 1-BASED, which is the
    one detail in this type that cannot be guessed from the field names. FPC
    writes `Dec(SystemTime.DayOfWeek)` in DateTimeToSystemTime and
    `DayOfWeek(...)-1` in the unix GetLocalTime -- both read, not inferred. So
    0 = Sunday in the FIELD, 1 = Sunday from the FUNCTION.

    First consumer: FPC's own compiler (globals.pas `startsystime`,
    `getrealtime(const st: TSystemTime)`), which reads Year/Month/Day and
    Hour/Minute/Second/MilliSecond -- the plain arm. }
  TSystemTime = record
    case Integer of
      0: (Year, Month, Day, DayOfWeek: Word;
          Hour, Minute, Second, MilliSecond: Word);
      1: (wYear, wMonth, wDay, wDayOfWeek: Word;
          wHour, wMinute, wSecond, wMilliseconds: Word);
  end;
  PSystemTime = ^TSystemTime;

const
  { Days from the TDateTime epoch (1899-12-30) to the Unix epoch (1970-01-01). }
  UnixDateDelta = 25569;

  { Days from 0001-01-01 to the TDateTime epoch (FPC SysUtils.DateDelta). }
  DateDelta = 693594;

  { FPC SysUtils.MonthDays[IsLeapYear(y)][month]. }
  MonthDays: array[False..True, 1..12] of Word = (
    (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31),
    (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31));

type

  { Pascal's exception root — a SIBLING of pylib's class of the same name, both
    descending from `ExceptionBase`. Two classes named `Exception`, one root.

    That shape is the whole design, and each half of it is load-bearing:
    - SIBLINGS, because `CreateFmt` cannot merge. Ours calls the real `Format`
      and pads (`CreateFmt('[%5d]',[3])` is `[    3]`, which is FPC parity);
      pylib's does minimal substitution because it must not drag sysutils into
      every `.npy`. Each unit keeps its own body and no hook is needed.
    - ONE ROOT, because `msg` and `argsv` then sit at ONE offset for every
      exception in either tree. That is what retires the old bridge: a NilPy
      `except Exception:` binds `ExceptionBase` and catches an RTL raise by
      INHERITANCE rather than by the frontend checking two hierarchies and a
      `msg`-must-be-first layout contract nothing kept in step.
    - BOTH NAMED `Exception`, because `ClassName` reports the DECLARED name, so
      Python's `repr(e)` and `type(e).__name__` come out right with no rename.

    So `msg`, `FHelpContext`, `HelpContext`, `FMessage` and `Message` are NOT
    redeclared here — they are inherited, and redeclaring any of them would
    reintroduce the two-layouts-one-name bug this replaced. }
  { Delphi's PResStringRec. FPC spells the same parameter `PString`; this unit
    does NOT, because `lib/rtl/typinfo.pas` already exports a `PString` that is
    a pointer to the WORD-prefixed frozen string kind, for reading RTTI name
    blobs (typinfo spells it `string[256]`, and the 256 is a kind selector, not
    a length — see the comment there) — and a
    program doing `uses typinfo, sysutils` would silently get whichever came
    last. Two incompatible meanings for one name in one RTL is the kind of thing
    that produces a wrong answer rather than an error, so the Delphi spelling is
    used here and the FPC one is left alone. Callers write `@SSomeString` and
    never name the type. }
  PResStringRec = ^string;

  Exception = class(ExceptionBase)
    constructor Create(const msg: string);
    constructor CreateFmt(const msg: string; const args: array of const);
    { The resource-string constructors. `CreateRes(@SArgumentOutOfRange)` is the
      Delphi/FPC idiom and the shape vendored code uses.

      WHAT THIS ACTUALLY DOES, since the name promises more than it delivers:
      it DEREFERENCES the pointer and constructs. There is no resource-string
      mechanism behind it — no translation table, no runtime replacement. That
      is a deliberate choice rather than a stub: the observable behaviour is
      identical to FPC's for a program that never re-translates, which is every
      program in the corpora, and a real mechanism can be slid underneath
      without changing this signature.

      NO LONGER BLOCKED (2026-08-28). This paragraph used to say `@SFoo` was
      `error: undefined variable` because a resourcestring section was parsed as
      a plain const section and a const has no address. It is now parsed as
      initialised string STORAGE — which is what FPC's runtime-replaceable
      resourcestring actually is — so `CreateRes(@SArgumentOutOfRange)` compiles
      and runs. [[bug-p-a-resourcestring-is-not-addressable]], resolved.
      These constructors still work with any `^string`.

      One deliberate divergence, in FPC's favour: FPC REFUSES a direct
      `SFoo := 'x'` (*Variable identifier expected*) while pxx accepts it, since
      ours is an ordinary initialised variable. That is the "we accept a form FPC
      rejects" row of CLAUDE.md's compat table — not a defect, and writing
      THROUGH the pointer works in both. }
    constructor CreateRes(ResString: PResStringRec);
    constructor CreateResFmt(ResString: PResStringRec; const args: array of const);
  end;

  { FPC System.TMethod: the two words a method pointer is made of. A `procedure of
    object` value has exactly this layout -- Code at +0, Data (Self) at one
    pointer width -- so code that builds a method pointer by hand fills a
    TMethod and casts it to the method type. fpcunit's TTestCase.RunBare does
    that to invoke a test method found by RTTI.

    The RECORD is not declared here, only its pointer: the compiler mints
    System.TMethod unconditionally (RegisterBuiltinTMethod), as FPC declares it
    in `system` and sysutils does not. See the longer note in typinfo.pas on why
    a same-shaped local copy is not harmless -- record parameters match
    NOMINALLY, so a duplicate silently makes the two spellings non-interchangeable
    at every call boundary while every layout assertion still passes.
    feature-p-tmethod-record-for-method-pointers }
  PMethod = ^TMethod;

  { FPC's standard SysUtils exception hierarchy. Real classes, not aliases: code catches them
    by type (`on E: EConvertError do`) and `is`/`as` must distinguish them, so each needs its
    own identity. Only the ones real code raises and catches are here; adding another is one
    line and no thought. }
  EAbort            = class(Exception) end;
  EConvertError     = class(Exception) end;      { StrToInt/StrToFloat on malformed input }
  EInOutError       = class(Exception) end;
  EAccessViolation  = class(Exception) end;
  EInvalidCast      = class(Exception) end;   { a failed `as` downcast }
  EIntError         = class(Exception) end;
  EDivByZero        = class(EIntError) end;      { INTEGER division by zero }
  ERangeError       = class(EIntError) end;
  EIntOverflow      = class(EIntError) end;
  { The FLOAT family, and it descends from EMathError rather than from Exception
    -- verified against fpc 3.2.2, which answers EInvalidOp.InheritsFrom(
    EMathError) = TRUE and EDivByZero.InheritsFrom(EMathError) = FALSE. The two
    trees are deliberately separate in FPC: EIntError for the integer unit,
    EMathError for the FPU one, and `on E: EMathError` is how real code catches
    "any float error". EInvalidOp used to descend from Exception here, so that
    idiom caught nothing. Found 2026-09-06 attempting uPSCompiler, which catches
    EZeroDivide and EMathError by name. }
  EMathError        = class(Exception) end;
  EInvalidOp        = class(EMathError) end;
  EZeroDivide       = class(EMathError) end;     { FLOAT division by zero }
  EOverflow         = class(EMathError) end;
  EUnderflow        = class(EMathError) end;
  EInvalidPointer   = class(Exception) end;
  EOutOfMemory      = class(Exception) end;
  { fpc sysutilh.inc:206 declares it straight off Exception with a public
    ErrorCode, and ExecuteProcess is the only thing in this unit that raises it.
    Added for the FPC-compiler-source march: cfileutl.pas:136 declares two
    RequotedExecuteProcess overloads taking `Flags: TExecuteFlags = []`, a type
    this unit did not have, and 127 of FPC's 207 compiler units queued behind
    it -- a QUEUE POSITION, not a size, since this umbrella has measured a
    cleared wall yielding three units four separate times. }
  EOSError          = class(Exception)
  public
    ErrorCode: Longint;
  end;
  EAssertionFailed  = class(Exception) end;
  ENotImplemented   = class(Exception) end;
  { fpc 3.2.2 sysutilh.inc:225 declares it straight off Exception, not off
    ENotImplemented -- the two read as synonyms and are siblings. fcl-passrc's
    pparser.pp raises it for a second source file. }
  ENotSupportedException = class(Exception) end;
  EArgumentException = class(Exception) end;
  { Delphi/FPC make this a DESCENDANT of EArgumentException, not a sibling, so
    `on E: EArgumentException` catches it. Generics.Defaults raises it 3 times;
    Generics.Collections many more. }
  EArgumentOutOfRangeException = class(EArgumentException) end;
  EListError        = class(Exception) end;
  { Raised when a Variant cannot be brought to the requested type — text that
    is not numeric read as a number, a Null read as a string. Declared HERE and
    not in `variants` (which is where it used to live, and which re-exports it)
    for one reason: the builtin units raise it through PXXVariantErrorHook, and
    the hook has to be installed by a unit that is present. `uses variants` is
    optional in pxx — variant support is in the compiler — while sysutils is
    what every program that catches anything already has. }
  EVariantError     = class(Exception) end;

  { FPC's System.TRuntimeError, in FPC 3.2.2's own declared order — read off a
    running FPC program rather than recalled, because the tail is NOT Delphi's
    (FPC ends reQuit / reCodesetConversion / reNoDynLibsSupport / reThreadError
    where Delphi has the monitor errors). 29 members; `reRangeError` is 4.
    Ordinals are faithful so a vendored `case` or a raw Ord() comparison means
    the same thing unmodified. }
  TRuntimeError = (
    reNone, reOutOfMemory, reInvalidPtr, reDivByZero, reRangeError,
    reIntOverflow, reInvalidOp, reZeroDivide, reOverflow, reUnderflow,
    reInvalidCast, reAccessViolation, rePrivInstruction, reControlBreak,
    reStackOverflow, reVarTypeCast, reVarInvalidOp, reVarDispatch,
    reVarArrayCreate, reVarNotArray, reVarArrayBounds, reAssertionFailed,
    reExternalException, reIntfCastError, reSafeCallError, reQuit,
    reCodesetConversion, reNoDynLibsSupport, reThreadError);

  { The metaclass of Exception. FPC declares it in System, but our Exception lives
    here, so here is where `class of` it can be formed. Code that catches by class
    (fpcunit records the expected exception class of a test) needs it. }
  ExceptClass = class of Exception;

  { The System hook that renders a code address for a backtrace line. FPC lets a
    program replace it (a symbolising debugger, a line-info unit); the default just
    formats the address. fpcunit's AddrsToStr feeds it CallerAddr's result to say
    WHERE an assertion failed. }
  TBackTraceStrFunc = function(Addr: Pointer): string;

var
  { Replaceable; defaults to SysBackTraceStr below. }
  BackTraceStrFunc: TBackTraceStrFunc;

{ FPC System.ExceptAddr / System.ExceptObject: the address at which the CURRENT
  exception was raised, and the object being raised. Both are real now -- the
  raise stub parks each in its own BSS slot and a compiler intrinsic reads it.
  (The comment here used to say ExceptAddr was a nil stub; that was true until
  bug-pascal-exceptaddr-returns-nil closed.)

  Both answer nil when no exception is in flight, and both stay valid only for as
  long as the exception is: inside an `except` block, or in a routine the handler
  calls. ExceptObject is the way to reach the object from a handler written WITHOUT
  an `on E: T do` binding --

    except
      WriteLn('caught ', ExceptObject.ClassName);
    end;

  -- which is exactly the shape FPC code that predates `on ... do` uses. }
function ExceptAddr: Pointer;
function ExceptObject: TObject;

{ FPC's System.Error: signal a runtime error. Declared here rather than in System
  because our Exception hierarchy is here and this raises through it.

  IT RAISES, IT DOES NOT HALT SILENTLY, AND THE ERROR NUMBERS ARE NOT FPC'S.
  Both halves are deliberate. Raising is the faithful behaviour in effect: an
  FPC program that has `uses sysutils` gets its runtime errors converted to
  exceptions by the RTL's error hook, so `Error(reRangeError)` there surfaces as
  a catchable ERangeError, which is exactly what this does directly. Not matching
  FPC's numbering is CLAUDE.md's standing ruling — a strict flag governs how
  source is COMPILED, not how a program DIES; "we seek LANGUAGE compliance, not
  error-handling compliance". So the mapping below is to OUR exception classes.

  Every one of the 7 call sites in `generics.defaults.pas` is the `else` arm of
  a case over a type kind — "this cannot happen" — so none of them depends on a
  code, only on the program stopping and saying something. A kind with no closer
  class raises a plain Exception naming the TRuntimeError member, which is more
  than a bare halt would say. }
procedure Error(RuntimeError: TRuntimeError);

{ FPC's SysUtils declares this (sysutilh.inc:243) and real code calls it as a
  bare statement rather than raising the class itself -- rtl-generics does, five
  times, in the grow paths of TCustomList and the dictionaries, which is where
  the rung-6b corpus probe met `undefined variable (OutOfMemoryError)`.
  EOutOfMemory already existed here; only the procedure was missing. }
procedure OutOfMemoryError;

{ The default BackTraceStrFunc: '  $00000000004012AB'. A nil address renders as
  $0, which is what the callers' "no address known" path already expects. }
function SysBackTraceStr(Addr: Pointer): string;

{ Int64 -> decimal string (covers Integer via widening). Handles negatives. }
function IntToStr(value: Int64): AnsiString; overload;

{ QWord -> UNSIGNED decimal string. A family and not one Int64 routine for the
  same reason IntToHex is one: without this arm a QWord argument widens into
  the signed spelling and every value at or above 2^63 comes back negative --
  IntToStr(High(QWord)) answered -1 while WriteLn of the same variable printed
  18446744073709551615, so one program rendered one value two ways.
  ([[bug-b-inttostr-of-a-qword-prints-it-signed]]) }
function IntToStr(value: QWord): AnsiString; overload;

{ FPC SysUtils.UIntToStr: the explicit unsigned spelling, and the one place the
  unsigned digit loop lives -- IntToStr(QWord) and Format's '%u' both route
  here, so signedness is decided once rather than per caller. }
function UIntToStr(value: QWord): AnsiString; overload;
function UIntToStr(value: Cardinal): AnsiString; overload;

{ Uppercase hexadecimal of value, left-zero-padded to at least Digits chars
  (FPC SysUtils.IntToHex). Negative values use their two's-complement bits —
  OF THEIR OWN WIDTH, which is why this is a family and not one Int64 routine:
  with only the Int64 spelling a 32-bit Integer is sign-extended before the
  routine sees it, so IntToHex(-1, 8) printed FFFFFFFFFFFFFFFF where FPC prints
  FFFFFFFF. Digits is a MINIMUM, so the extra F's could not be trimmed back off.
  ([[bug-b-inttohex-of-a-negative-integer-prints-16-digits]]) }
function IntToHex(value: Int64; digits: Integer): AnsiString; overload;
function IntToHex(value: LongInt; digits: Integer): AnsiString; overload;
function IntToHex(value: LongWord; digits: Integer): AnsiString; overload;

{ FPC System.HexStr(Value, Digits): uppercase hex, left-zero-padded to Digits. Same result
  as IntToHex; declared because FPC code calls it by this name (fpjson escapes a character
  as `'\u' + HexStr(Ord(S[I]), 4)`). }
function HexStr(Value: Int64; Digits: Integer): AnsiString;

{ A string of Count copies of ch (FPC SysUtils.StringOfChar; '' if Count<=0). }
{ StringOfChar stays HERE, with LowerCase / StrLen / StrPas / SysBackTraceStr,
  for one reason that is about the PIN and not about the names: something built
  with $(PXX_STABLE) calls it -- test/lib_strpchar.pas, a lib-test row -- and
  that build sees the PINNED compiler and a FROZEN copy of compiler/builtin, so
  a name moved out of this unit vanishes from the only place it can look.
  Measured: moving it made `make lib-test` fail with
  `undefined variable (StringOfChar)` at lib_strpchar.pas:49.
  The finishing trigger for all five is in compiler/builtin/builtin.pas.
  task-b-nineteen-sysutils-names-that-fpc-keeps-in-system }
function StringOfChar(ch: Char; count: Integer): AnsiString;

{ 1-based substring; count clamped to the end; out-of-range index -> ''. }
function Copy(const s: AnsiString; index, count: Integer): AnsiString;
{ Copy(s, index): the rest of s from index, FPC's two-argument form. }
function Copy(const s: AnsiString; index: Integer): AnsiString;

{ FPC's `Ch in CSet`, spelled as a function. TSysCharSet has been declared above
  for a while and its own comment already named this as "the parameter type of
  the CharInSet / character classification family" -- the type was here, named
  after the function, and the function was not. Delphi-compatible code calls it
  unconditionally because `Ch in Set` is not writable when Ch is a WideChar.
  fcl-passrc pscanner.pp:559. feature-b-sysutils-charinset }
function CharInSet(Ch: AnsiChar; const CSet: TSysCharSet): Boolean;

{ FPC's SysUtils.AnsiDequotedStr: strip one surrounding pair of AQuote and
  collapse each DOUBLED quote inside to one.

  THE THREE NON-OBVIOUS CASES ARE FPC'S, NOT CHOICES, and each has a row in the
  test: a string that does not START with the quote is returned WHOLE and
  unexamined (FPC's AnsiExtractQuotedStr does `exit(strpas(P))` there, so
  `ab'cd` keeps its inner quote); an UNTERMINATED quote consumes to the end
  rather than failing; and a doubled quote is an escape, so `'ab''c'` is `ab'c`.
  Written over the string rather than over a PChar because pxx has no need of
  FPC's `var Src: PChar` cursor, which exists so AnsiExtractQuotedStr can report
  where it stopped -- a caller nothing here has.
  fcl-passrc pparser.pp:4467. feature-b-sysutils-charinset (which covers both) }
function AnsiDequotedStr(const S: AnsiString; AQuote: Char): AnsiString;

{ Strip characters <= ' ' (spaces, tabs, control) from both ends. }
function Trim(const s: AnsiString): AnsiString;

{ Parse a decimal integer. StrToIntDef returns def on any malformed input;
  StrToInt returns 0 on malformed. Leading spaces and a +/- sign are allowed. }
function StrToIntDef(const s: AnsiString; def: Integer): Integer;
function StrToInt(const s: AnsiString): Integer;
function StrToInt64Def(const s: AnsiString; def: Int64): Int64;

{ FPC codepage identifiers. This RTL is byte-transparent -- it neither decodes nor recodes --
  and the bytes it carries through are whatever the source gave it, which for JSON/HTTP/etc is
  UTF-8. So DefaultSystemCodePage reports CP_UTF8, and code that asks "do I need to convert?"
  correctly concludes it does not. That is the honest answer for this string model, not a
  placeholder. Note it stays CP_UTF8 even under {$define PXX_WIDE_PAYLOAD}: the define changes
  what a UnicodeString holds, not what an AnsiString holds, and this constant is about the byte
  string. UTF8Decode above is where the two models meet. }
const
  CP_ACP   = 0;
  CP_UTF16 = 1200;
  CP_UTF8  = 65001;
  CP_NONE  = $FFFF;

var
  DefaultSystemCodePage: Word;

{ FPC SysUtils.FreeAndNil: free the object and nil the reference, in that order. The parameter
  is UNTYPED (`var Obj`) exactly as in FPC, so any class-typed variable can be passed without a
  cast. Niling AFTER the free is the point of it: a destructor that re-enters and reads the
  variable sees nil, not a dangling pointer. }
procedure FreeAndNil(var Obj);

{ FPC System.StrPas: a NUL-terminated PChar as a Pascal string ('' for nil). StrLen is its
  length. }
function StrPas(P: PChar): AnsiString;
function StrLen(P: PChar): Integer;

{ FPC's sLineBreak: the platform line terminator. `LineEnding` is a compiler-known constant
  in this dialect; sLineBreak is the SysUtils spelling of the same thing, which FPC code uses
  interchangeably (fpjson's pretty-printer builds its indentation with it). }
function sLineBreak: AnsiString;
{ ^ RESTORED HERE 2026-09-11, DELIBERATELY DUPLICATING the copy in
  compiler/builtin/builtin.pas -- and the duplicate is what makes the pair
  COHERENT, not what makes it incoherent. The move on 2026-09-09 (0ffe185bb)
  deleted six names from this unit and left them only in the compiler's own
  System unit. That is correct at HEAD and it took out every consumer that
  builds with $(PXX_STABLE), because that build sees the PINNED compiler and a
  FROZEN copy of compiler/builtin/ which predates the move: the name is gone
  from the only two places such a build can look.
  MEASURED on seven, not inferred -- `undefined variable (SetString)` in
  external/synapse/synautil.pas took out all three lib_synapse rows, and
  `undefined variable (UTF8Encode)` in testjsondata.pp took out test-fpjson.
  Those four rows are named FIRST in every refusal that names them at all -- 41
  of 64 post-arming verdicts when this was written, and N is still growing,
  because the watcher is still publishing. The other 23 are led by
  optdiff#shard0/12, which no RTL change can clear. So the cliff this minted was
  blocking the pin for 41 of them and the pin was never one fix away: quote the
  shape (whenever these rows appear they lead) and not a bare count, because a
  reader who re-derives a live denominator cannot tell a stale figure from a
  wrong one.
  ALL SIX ARE RESTORED, not just the two that were measured. The population for
  "who calls this" is everything the PINNED build compiles, external corpora
  included, and external/ is absent on plexus -- so it cannot be enumerated
  from here, only guessed at. That guess has now cost three rounds (LowerCase
  and friends, then StringOfChar, then these four rows) and a fourth is not
  worth the lines it would save.
  THE DUPLICATE IS NOT A SECOND SOURCE OF TRUTH IN PRACTICE, and that is
  measured too: FloatToStr, FloatToExpStr and HexStr are declared in this unit
  AND in builtin.pas today, in the frozen copy as well as the live one, and
  have been for as long as lib-test has been green.
  IF YOU FOUND THIS COLD AND IT LOOKS LIKE A REGRESSION TO CLEAN UP: deleting
  either copy today re-breaks four tstate rows. Delete the BUILTIN copy and a
  program with no `uses` line loses all six names again, which is the defect
  0ffe185bb fixed. Delete THIS copy and external/synapse and fpjson stop
  compiling under $(PXX_STABLE), which is the defect 0ffe185bb caused. Both
  copies are load-bearing until the pin moves, and only then does one stop
  being.
  RETIRE IT by deleting the copy here -- declaration AND body -- once a pin's
  stable_linux_amd64/default/builtin/builtin.pas carries the name. Grep it
  there; that is the whole test.
  task-b-five-system-names-still-in-sysutils-are-waiting-on-a-pin-not-on-a-decision }

{ FPC's Try* parsers: return False on malformed input and leave the out value untouched,
  rather than raising. }
function TryStrToInt64(const s: AnsiString; var value: Int64): Boolean;
function TryStrToFloat(const s: AnsiString; var value: Double): Boolean;
function TryStrToQWord(const s: AnsiString; var value: QWord): Boolean;

{ FPC SysUtils.StrToBool / StrToBoolDef. Accepts the names ('true'/'false', case-insensitive)
  and the numeric form (0 = False, anything else True), as FPC does. StrToBool returns False
  on anything else (FPC raises; this RTL's other StrTo* return a default rather than raise,
  and this follows them). }
function StrToBool(const s: AnsiString): Boolean;
function StrToBoolDef(const s: AnsiString; def: Boolean): Boolean;

{ FPC's UTF-8 <-> UnicodeString converters.

  THESE ARE REAL NOW, AND THE BODIES DID NOT CHANGE TO MAKE THEM REAL. The whole conversion
  is in the two signatures: `UnicodeString` is the wide ELEMENT WIDTH of the one managed-string
  kind, so `Result := s` across a width boundary lowers to PXXWideFromStr / PXXStrFromWide
  automatically (feature-unicodestring-model step 7c). Writing the transcode out by hand here
  would be a SECOND implementation of it, and the second one is the one that stays broken.

  WHAT YOU GET DEPENDS ON THE PROGRAM, and that is not a hedge -- it is the migration. Under
  `{$define PXX_WIDE_PAYLOAD}` UnicodeString is genuinely UTF-16: UTF8Decode('café') answers
  4 code units for 5 UTF-8 bytes, indexing steps one CHARACTER as FPC's does, and a non-BMP
  code point is the surrogate PAIR that jsonscanner needs. Without the define UnicodeString
  is still an alias for the byte string, these are still the identity, and every existing
  program compiles to exactly what it compiled to before.

  So the old note on this declaration -- "there is no UTF-16 UnicodeString to convert TO" --
  was true when it was written and is now true only of the default build. It is corrected
  rather than deleted because a caller that relied on the identity is relying on something
  that still holds for them, and needs to know what turning the define on would change:
  one element per CHARACTER instead of one per BYTE. For ASCII, which is what fpjson's escaping
  actually walks, the two agree exactly either way. }
function UTF8Decode(const s: AnsiString): UnicodeString;
{ ^ RESTORED HERE 2026-09-11 as a deliberate duplicate of the copy in
  compiler/builtin/builtin.pas, because a $(PXX_STABLE) build sees the FROZEN
  builtin and cannot reach the moved name. The full note on sLineBreak carries
  the measurement and the retirement test. }
function UTF8Encode(const s: UnicodeString): AnsiString;
{ ^ RESTORED HERE 2026-09-11 as a deliberate duplicate of the copy in
  compiler/builtin/builtin.pas, because a $(PXX_STABLE) build sees the FROZEN
  builtin and cannot reach the moved name. The full note on sLineBreak carries
  the measurement and the retirement test. }

{ FPC SysUtils Int64/QWord parsers. StrToInt64/StrToQWord raise EConvertError on
  malformed input, like FPC; the *Def forms return the default instead. }
function StrToInt64(const s: AnsiString): Int64;
function StrToQWord(const s: AnsiString): QWord;
function StrToQWordDef(const s: AnsiString; def: QWord): QWord;

{ Index of the LAST char of S that occurs in Delimiters, 0 if none (FPC). }
function LastDelimiter(const Delimiters, S: AnsiString): Integer;

{ NOTE: no Val here -- `Val` is an intercepted builtin name and the builtin
  mis-lowers (wrong error code + segfault); a user Val is shadowed by it. See
  bug-builtin-val-miscompiles. Use StrToIntDef / StrToInt instead. }

{ ASCII case conversion. }
function UpCase(c: Char): Char;
function UpCase(const s: AnsiString): AnsiString;
function UpperCase(const s: AnsiString): AnsiString;
function LowerCase(const s: AnsiString): AnsiString;
{ FPC Ansi* variants: locale-aware there, plain ASCII here (this RTL is
  byte/ASCII throughout — same shape Synapse expects for header tokens). }
function AnsiUpperCase(const s: AnsiString): AnsiString;
function AnsiLowerCase(const s: AnsiString): AnsiString;

var
  { FPC locale format settings, fixed POSIX/C defaults here (no locale layer).
    Writable vars like FPC so code may override (Synapse rewrites time strings
    with TimeSeparator). }
  TimeSeparator: Char;
  DateSeparator: Char;
  DecimalSeparator: Char;
  { Field ORDER for StrToDate — only the y/m/d letters and their sequence are
    read, so 'd/m/y' and 'dd/mm/yyyy' parse alike. FPC's own C-locale default
    is 'd/m/y' with DateSeparator '-', which looks inconsistent and is not:
    '/' inside a format string MEANS "the date separator". }
  ShortDateFormat: AnsiString;
  { The time and long-date layouts DateToStr / TimeToStr / DateTimeToStr expand
    to. FPC's C-locale defaults, measured on fpc 3.2.2 under LANG=C:
    LongTimeFormat 'hh:nn:ss', ShortTimeFormat 'hh:nn',
    LongDateFormat 'dd" "mmmm" "yyyy'. Writable like FPC's. }
  LongTimeFormat: AnsiString;
  ShortTimeFormat: AnsiString;
  LongDateFormat: AnsiString;
  { A one- or two-digit year is placed in the 100 years ENDING at
    CurrentYear - TwoDigitYearCenturyWindow + 100, i.e. the window slides with
    the clock. FPC's default is 50. }
  TwoDigitYearCenturyWindow: Word;
  { Grouping and currency, for Format's '%n' and '%m'. FPC's own defaults are
    these regardless of the process locale (verified against fpc under both
    LANG=C and en_US.UTF-8), so hardcoding them IS the parity answer, not a
    stand-in for a locale layer. NegCurrFormat 5 is '-1$'; CurrencyFormat 1 is
    '1$' — value first, symbol suffixed, no space. }
  ThousandSeparator: Char;
  CurrencyString: AnsiString;
  CurrencyFormat: Byte;
  NegCurrFormat: Byte;
  CurrencyDecimals: Byte;
  { FPC's month/day name tables, 1-based (index 0 unused, as FPC declares them
    array[1..12] / array[1..7]). Synapse reads ShortMonthNames to build its RFC
    822 date parser's month table (synautil.pas), so the whole unit failed to
    compile without them. English/C defaults, writable like FPC's. }
  ShortMonthNames: array[1..12] of AnsiString;
  LongMonthNames: array[1..12] of AnsiString;
  ShortDayNames: array[1..7] of AnsiString;
  LongDayNames: array[1..7] of AnsiString;

type
  { FPC Currency is a fixed-point 4-decimal Int64; this RTL models it as
    Double (lossy past 2^52 — acceptable for the compat surface;
    Pascal Script's CurrToStr). }
  Currency = Double;

{ Float -> string. FloatToStr gives a compact representation; FloatToStrF
  gives fixed-point with precision digits after the decimal point.

  TWO overloads because the digit count is a property of the ARGUMENT'S WIDTH,
  exactly as in FPC: a Double gets 15 significant digits, a Single 10. With
  only the Double spelling a Single widened into it and printed its full Double
  expansion — 15 digits of a value that never had them:

    FloatToStr(Single(0.1))  was 0.100000001490116   FPC 0.1000000015
    FloatToStr(Single(1/3))  was 0.333333343267441   FPC 0.3333333433

  The digit count also decides when the exponent form kicks in, so the same one
  parameter fixes `Single(1e10)` printing as 10000000000 where FPC gives 1E10.
  ([[bug-b-floattostr-of-a-single-prints-15-digits-where-fpc-prints-10]]) }
function FloatToStr(value: Double): AnsiString; overload;
function FloatToStr(value: Single): AnsiString; overload;
{ FloatToStr with an explicit significant-digit count (1..15). Format's `%.Ng`
  is the caller that needs it; FloatToStr is this with FPC's fifteen. }
function FloatToStrSig(value: Double; sigDigits: Integer): AnsiString;
function FloatToExpStr(value: Double): AnsiString;
function FloatToStrF(value: Double; precision: Integer): AnsiString; overload;

{ FPC's FOUR-argument FloatToStrF — the only spelling real code uses, and it
  was a COMPILE ERROR here until now, because the two-argument form above is a
  pxx invention that happens to share the name. Both are kept: the short one has
  callers in examples/, and changing a signature out from under them is not a
  fix. This is an overload, not a replacement.

  The two Integer arguments mean DIFFERENT things per format, which is the
  trap — `Precision, Digits` reads like "before, after the point" and is not:

  | format      | Precision           | Digits                          |
  | ffFixed     | ignored             | digits AFTER the point          |
  | ffNumber    | ignored             | digits after the point, grouped |
  | ffCurrency  | ignored             | digits after the point          |
  | ffExponent  | SIGNIFICANT digits  | MINIMUM width of the exponent   |
  | ffGeneral   | SIGNIFICANT digits  | (unused in practice)            |

  Measured against fpc 3.2.2 under LC_ALL=C:

    FloatToStrF(1234.5678, ffFixed,    15, 2)  =  1234.57
    FloatToStrF(1234.5678, ffFixed,     2, 2)  =  1234.57      <- Precision ignored
    FloatToStrF(1234.5678, ffGeneral,   4, 0)  =  1235
    FloatToStrF(1234.5678, ffExponent,  5, 2)  =  1.2346E+03
    FloatToStrF(1234.5678, ffExponent, 15, 0)  =  1.23456780000000E+3
    FloatToStrF(1234567.891, ffNumber, 15, 2)  =  1,234,567.89
    FloatToStrF(-1234.5,   ffCurrency, 15, 2)  =  -1,234.50$

  Note ffExponent's exponent field has no fixed width: Digits 2 gives E+03 and
  Digits 0 gives E+3. Format's '%e' is the same routine pinned at three. }
function FloatToStrF(value: Double; format: TFloatFormat;
                     Precision, Digits: Integer): AnsiString; overload;

{ EXACT float -> string. Unlike FloatToStrSig, which normalises the mantissa by
  scaling in doubles and therefore cannot honestly offer more than 15
  significant digits, these two generate the double's exact decimal expansion
  with integer arithmetic. Every digit they print is a real digit of the value.

  FloatToStrExact asks for a specific number of significant digits (correctly
  rounded, half-to-even on the exact remainder, as %.*g does).
  FloatToStrShortest gives the shortest string that reads back as the SAME
  double — 17 digits always suffice, most values need far fewer, and this is
  what a faithful decimal form of a Double means. }
function FloatToStrExact(value: Double; sigDigits: Integer): AnsiString;
function FloatToStrShortest(value: Double): AnsiString;

{ String -> float. StrToFloatDef returns def on malformed; StrToFloat RAISES
  EConvertError, as FPC does and as the integer arms of this family already did. }
function StrToFloatDef(const s: AnsiString; def: Double): Double;
function StrToFloat(const s: AnsiString): Double;

{ FPC's non-raising PChar-taking parser — StrToFloat is defined in terms of it.
  True on success with Value set; False leaves Value alone. Measured against
  FPC 3.2.2: surrounding whitespace is TRIMMED ('  2.5  ' parses), but trailing
  junk is fatal ('1.5x' is False, not 1.5), and the empty buffer is False. }
function TextToFloat(Buffer: PChar; var Value: Extended): Boolean;

{ Currency <-> string. CurrToStr has existed in the implementation since the
  Currency type was added but was never declared here, so no caller outside
  this unit could reach it — `CurrToStr(c)` was an "undefined variable". }
function CurrToStr(C: Currency): AnsiString;
function StrToCurr(const s: AnsiString): Currency;
function StrToCurrDef(const s: AnsiString; def: Currency): Currency;

{ Return the position of substr in s, 1-based; 0 if not found. The offset
  form starts the search there; below 1 or past the end finds nothing (FPC). }
function Pos(const substr, s: AnsiString): Integer;
function Pos(const substr, s: AnsiString; offset: Integer): Integer;

{ Null-terminated PChar routines (FPC's `strings` unit, re-exported by SysUtils).
  StrLCopy copies at most MaxLen chars from Source up to its #0, always #0-
  terminates Dest, and returns Dest. StrLComp compares at most MaxLen chars,
  returning <0 / 0 / >0 like FPC (stops at the first #0 or difference). }
{ True when the Len bytes at P1 and P2 are identical (FPC SysUtils.CompareMem). }
function CompareMem(P1, P2: Pointer; Len: Int64): Boolean;

{ Ordering twin of CompareMem (FPC SysUtils.CompareMemRange): the sign of the
  first differing byte pair, 0 when the Len bytes match. Unsigned byte compare,
  like FPC — a byte >= 128 must sort ABOVE one below it, which a PChar (signed)
  compare would invert. rtl-generics' TCompare._Binary is the default comparer
  for every record type, so this is what `TComparer<TRec>.Default` runs on. }
function CompareMemRange(P1, P2: Pointer; Len: Int64): Integer;

{ FPC System.AllocMem: GetMem plus a zero-fill, returned as an untyped Pointer.

  IN SYSUTILS RATHER THAN A BUILTIN, and the placement is the measured half:
  FPC declares it in the implicit System unit so no `uses` is needed, and we have
  no implicit-unit slot for a library declaration. But the code that wants it —
  fcl-xml's `xmlutils.pp`, three sites — opens with `uses SysUtils, Classes`, and
  both are ours, so SysUtils is a place the caller already reaches. Same shape as
  IEnumerable<T> in classes.pas: FPC needing mechanism X for reason R does not
  mean we need X when the caller's own uses clause already solves R.

  The zero-fill is the entire difference from GetMem and it is not optional —
  `FBucket := AllocMem(I * sizeof(PHashItem))` is a hash table of pointers then
  tested against nil, so an unzeroed block reads as fully populated with garbage
  addresses. A GetMem alias would compile everywhere and crash later. }
function AllocMem(Size: PtrUInt): Pointer;
{ ^ RESTORED HERE 2026-09-11 as a deliberate duplicate of the copy in
  compiler/builtin/builtin.pas, because a $(PXX_STABLE) build sees the FROZEN
  builtin and cannot reach the moved name. The full note on sLineBreak carries
  the measurement and the retirement test. }

{ Element count of the dynamic array whose handle is P, 0 for nil (FPC
  System.DynArraySize). The count is the managed-block header's length word at
  P-8 — the same slot Length() reads — so this is Length() reached through an
  untyped Pointer, which is what a generic comparer has: rtl-generics'
  TCompare._DynArray is handed two `constref ... : Pointer` and must size them
  without knowing the element type. See devdocs/dev/managed-block-header.md. }
function DynArraySize(P: Pointer): Int64;
{ ^ RESTORED HERE 2026-09-11 as a deliberate duplicate of the copy in
  compiler/builtin/builtin.pas, because a $(PXX_STABLE) build sees the FROZEN
  builtin and cannot reach the moved name. The full note on sLineBreak carries
  the measurement and the retirement test. }

function StrLCopy(Dest, Source: PChar; MaxLen: Cardinal): PChar;
function StrLComp(Str1, Str2: PChar; MaxLen: Cardinal): Integer;

{ The rest of the PChar family, exactly as FPC's SysUtils re-exports it (see
  rtl/objpas/sysutils/syspchh.inc). Real FPC code writes `uses SysUtils` and
  calls StrPCopy/StrNew/StrScan without ever naming the `strings` unit — half
  the family was reachable here and half was not, which is the worst shape: the
  code compiles up to its second call and then stops.

  These are thin forwards to `strings`, NOT a second implementation — the
  contracts (and their traps: StrNew('') = nil, StrECopy returning the
  end-cursor rather than Dest, StrBufSize's hidden 4-byte prefix) are documented
  once, in lib/rtl/strings.pas, and measured against FPC there. }
function StrCopy(Dest, Source: PChar): PChar;
function StrCat(Dest, Source: PChar): PChar;
function StrComp(Str1, Str2: PChar): Integer;
function StrIComp(Str1, Str2: PChar): Integer;
function StrEnd(P: PChar): PChar;
function StrScan(P: PChar; C: Char): PChar;
function StrRScan(P: PChar; C: Char): PChar;
function StrPos(Str1, Str2: PChar): PChar;
function StrECopy(Dest, Source: PChar): PChar;
function StrMove(Dest, Source: PChar; L: Integer): PChar;
function StrUpper(P: PChar): PChar;
function StrLower(P: PChar): PChar;
function StrPCopy(Dest: PChar; const Source: AnsiString): PChar;
function StrPLCopy(Dest: PChar; const Source: AnsiString; MaxLen: Integer): PChar;
function StrAlloc(Size: Integer): PChar;
function StrBufSize(Str: PChar): Integer;
function StrNew(P: PChar): PChar;
procedure StrDispose(Str: PChar);

{ Suspend the current thread for at least Milliseconds (FPC SysUtils.Sleep).
  Backed by the nanosleep syscall. }
procedure Sleep(Milliseconds: Cardinal);

{ Move/FillChar are now compiler builtins (compiler/builtin/builtin.pas,
  auto-pulled, FPC System parity) — registered first, so FindProc resolves every
  call to them. The former interim SysUtils copies were removed
  (task-remove-sysutils-move-fillchar-copies). }

{ Left-pad/Right-pad s to len chars with ch (default space). }
function PadLeft(const s: AnsiString; len: Integer; ch: Char): AnsiString;
function PadRight(const s: AnsiString; len: Integer; ch: Char): AnsiString;

{ `Delete(var s; index, count)` and `Insert(const src; var dst; index)` are NOT
  declared here, and that is deliberate. fpc keeps both in `system`, not in
  `sysutils`, and pxx lowers both to intrinsics (__pxxStrDelete / __pxxStrInsert
  for a string, AN_DYN_DELETE / AN_DYN_INSERT for a dynamic array).

  A same-named routine in scope CLOSES the intrinsic for EVERY argument shape,
  because SoftIntrinsicOpen is asked before any argument is parsed. So while
  these two lived here, one `uses sysutils` took dynamic-array Delete and Insert
  away from the program -- `Delete(arr, 1, 2)` answered `no overload of Delete
  matches these arguments`, offering the string overload as the only candidate.
  fpc compiles it. Three defects came from this one declaration; the third is
  bug-a-the-import-escape-hatch-fails-on-classes-pas, where TStrings'
  bare `Delete(Index)` bound the string overload and classes.pas failed to
  compile under NilPy while compiling clean under Pascal.

  If you are tempted to add them back for a target without the builtin unit:
  measured 2026-09-06, `uses sysutils` does not compile on `--esp-profile=bare`
  at all (lib/rtl/strings.pas's UpCase needs the same builtin unit), so no ESP
  program could ever reach these bodies. EspBareBoot is the only profile that
  excludes the builtin unit. bug-p-one-uses-sysutils-removes-dynamic-array-delete-and-insert }

{ Concatenate two strings. For more than two, chain with + or nest calls. }
function Concat(const s1, s2: AnsiString): AnsiString;

{ Lexicographic compare by byte value: <0 / 0 / >0. Uses char codes (the string
  relational operators are unreliable — see bug-string-ordering-comparison-constant
  — so this is the correct comparator and what Sort etc. should call). }
function CompareStr(const s1, s2: AnsiString): Integer;
{ Case-insensitive CompareStr; SameText is its = 0 form. }
function CompareText(const s1, s2: AnsiString): Integer;

{ FPC's locale-aware comparators. This RTL is byte/ASCII throughout (no locale
  layer), so they are the plain CompareStr / CompareText -- same contract, same
  sign convention. Declared because FPC code calls them by name. }
function AnsiCompareStr(const s1, s2: AnsiString): Integer;
function AnsiCompareText(const s1, s2: AnsiString): Integer;

{ The Wide/Unicode spellings of the same two comparators. This RTL has ONE
  string model -- bytes -- and `WideString`/`UnicodeString` ARE `string` here
  (see the UTF-8 converter note above), so these are the Ansi pair verbatim
  rather than a second implementation. Declared because FPC code names them:
  rtl-generics' TCompare.WideString/UnicodeString call them to build the default
  comparer for those types. }
function WideCompareStr(const s1, s2: AnsiString): Integer;
function WideCompareText(const s1, s2: AnsiString): Integer;
function UnicodeCompareStr(const s1, s2: AnsiString): Integer;
function UnicodeCompareText(const s1, s2: AnsiString): Integer;
function SameText(const s1, s2: AnsiString): Boolean;
function AnsiSameText(const s1, s2: AnsiString): Boolean;

{ The case-SENSITIVE twins of SameText / AnsiSameText. FPC has both pairs and
  real code reaches for SameStr precisely when it does NOT want folding, so
  routing it to SameText would be a silent wrong answer, not a shortcut.
  Measured: AnsiSameStr('a','A') is False, AnsiSameStr('','') is True. }
function SameStr(const s1, s2: AnsiString): Boolean;
function AnsiSameStr(const s1, s2: AnsiString): Boolean;

{ FPC's AnsiPos. Byte-identical to Pos on this RTL (one string model, no locale
  layer) and declared because FPC code names it. The empty needle answers 0 —
  same as Pos, and the same trap StrUtils' AnsiContainsStr inherits. }
function AnsiPos(const substr, s: AnsiString): Integer;

{ Strip leading / trailing chars <= ' '. }
function TrimLeft(const s: AnsiString): AnsiString;
function TrimRight(const s: AnsiString): AnsiString;

{ Is Ident a legal Pascal identifier? With AllowDots, a dotted name
  (`Unit.Thing`) is legal too; StrictDots additionally forbids a trailing dot
  and requires each segment to start a fresh identifier. FPC's own signature
  (rtl/objpas/sysutils/sysstrh.inc:114) -- both flags default False, so the
  one-argument spelling fcl-passrc's pscanner.pp uses gets the plain rule. }
function IsValidIdent(const Ident: AnsiString; AllowDots: Boolean = False;
                      StrictDots: Boolean = False): Boolean;

{ The leftmost / rightmost Count characters of S. THESE LIVE IN SysUtils IN FPC
  (rtl/objpas/sysutils/sysstrh.inc, under "extra functions"), not only in
  StrUtils -- which is easy to disbelieve, because StrUtils is where the rest of
  the family is and where Delphi puts them. fcl-passrc's pscanner.pp calls them
  with `uses SysUtils, Classes` and nothing else, so a unit that never mentions
  StrUtils is entitled to them. Found by frankD running fcl-passrc against the
  compiler; the two lines were `undefined variable (LeftStr)`.
  Count is clamped, so a Count outside 0..Length(S) yields '' or the whole
  string rather than an error -- FPC's own behaviour, which reaches the same
  answers through Copy's clamping rather than by testing. }
function LeftStr(const S: AnsiString; Count: Integer): AnsiString;
function RightStr(const S: AnsiString; Count: Integer): AnsiString;

{ Parse a decimal integer; True + value on success, False (value untouched) on
  any malformed input. }
function TryStrToInt(const s: AnsiString; var value: Integer): Boolean;

{ Replace occurrences of OldPattern in S with NewPattern. rfReplaceAll replaces
  every occurrence (else only the first); rfIgnoreCase matches case-insensitively. }
function StringReplace(const S, OldPattern, NewPattern: AnsiString; Flags: TReplaceFlags): AnsiString;

{ Wrap s in single quotes, doubling any embedded quote. }
{ the general form QuotedStr is a special case of: quote with any character,
  doubling that character where it occurs in the text }
function AnsiQuotedStr(const s: AnsiString; quote: Char): AnsiString;
function QuotedStr(const s: AnsiString): AnsiString;

{ printf-style formatting over an `array of const`. Specifiers: %d %u %x %s %f
  %g %c %%, with width, '-' (left-align) / '0' (zero-pad) flags, and .precision
  (max chars for %s, fraction digits for %f). FPC SysUtils.Format. }
function Format(const fmt: AnsiString; const args: array of const): AnsiString;

{ FPC SysUtils.BoolToStr. With UseBoolStrs the result is 'True'/'False'; without it
  the Delphi-compatible '-1'/'0'. The TrueS/FalseS form lets the caller name both. }
function BoolToStr(B: Boolean; UseBoolStrs: Boolean = False): AnsiString; overload;
function BoolToStr(B: Boolean; const TrueS, FalseS: AnsiString): AnsiString; overload;

{ FPC's UnicodeString-returning Format. This RTL has a single byte-string model
  (string = AnsiString), so it is Format -- declared because FPC code calls it by
  name (fpcunit's ComparisonMsg does). }
function UnicodeFormat(const fmt: AnsiString; const args: array of const): AnsiString;

{ Path helpers (POSIX '/' delimiter; '\' also accepted as a separator). }
function ExtractFileName(const path: AnsiString): AnsiString;   { after last sep }
function ExtractFilePath(const path: AnsiString): AnsiString;   { up to & incl last sep }
function ExtractFileDir(const path: AnsiString): AnsiString;    { up to last sep, excl }
function ExtractFileExt(const path: AnsiString): AnsiString;    { last '.ext' incl dot }
function ChangeFileExt(const path, ext: AnsiString): AnsiString;
function IncludeTrailingPathDelimiter(const path: AnsiString): AnsiString;
function ExcludeTrailingPathDelimiter(const path: AnsiString): AnsiString;
{ Rewrite every accepted separator to the native one. On POSIX that is '/', so
  a '\' written by a DOS/Windows-minded caller is normalised rather than left
  to be read as part of a filename. FPC spells the in-place half
  DoDirSeparators; only the functional half has callers here. }
function SetDirSeparators(const path: AnsiString): AnsiString;

{ List directory entries, excluding "." and "..". Size and modification time are
  filled when the active PAL backend supports metadata, otherwise Size is -1. }
function GetDirectoryContents(const path: AnsiString; var list: TFileInfoArray): Boolean;

{ Execute a process in a pipeline, returning its PID and redirecting stdin/stdout via pipes if requested. }
function ExecutePipeline(const cmd: AnsiString; const args: array of AnsiString; var childStdinFd, childStdoutFd: Integer): Integer;

{ Gregorian calendar <-> TDateTime (days since 1899-12-30, FPC/Delphi's
  epoch). EncodeDate/DecodeDate handle the whole-day part; EncodeTime/
  DecodeTime the time-of-day fraction. Year 0 and negative years are
  proleptic-Gregorian (there is no explicit valid-range check here, matching
  FPC's own leniency in practice for this RTL's scope). }
function EncodeDate(Year, Month, Day: Word): TDateTime;
procedure DecodeDate(aDate: TDateTime; out Year, Month, Day: Word);
function EncodeTime(Hour, Min, Sec, MSec: Word): TDateTime;
procedure DecodeTime(aTime: TDateTime; out Hour, Min, Sec, MSec: Word);

{ 1..7, 1 = Sunday (FPC/Delphi convention). The epoch day 0 (1899-12-30) was
  a Saturday = 7. First consumer: Synapse synautil's RFC-822 date rendering
  (feature-synapse-compile-check). }
function DayOfWeek(DateTime: TDateTime): Integer;

{ TSystemTime <-> TDateTime, and the wall clock as a TSystemTime.

  GetLocalTime IS UTC HERE, and that is this RTL's existing stance rather than
  an oversight: `Now` reads CLOCK_REALTIME through the PAL and there is no
  timezone database (see Now's own note above, and the POSIX/C fixed-locale
  position). FPC's unix GetLocalTime applies the zone; ours cannot, so it
  agrees with OUR Date/Time/Now rather than disagreeing with them. A program
  that formats what GetLocalTime returns gets a consistent answer; one that
  compares it against an external local timestamp does not, and that is the
  same limitation Now already carries.

  MilliSecond is real, not a zero: Now is built on PalRealtime's nanoseconds. }
procedure GetLocalTime(var SystemTime: TSystemTime);
procedure DateTimeToSystemTime(DateTime: TDateTime; out SystemTime: TSystemTime);
function SystemTimeToDateTime(const SystemTime: TSystemTime): TDateTime;

{ Gregorian leap-year test (FPC SysUtils.IsLeapYear). }
function IsLeapYear(Year: Word): Boolean;

{ Shift a date by NumberOfMonths whole months, clamping the day to the target
  month's length — the clamp is the whole point and the part worth reading off
  an FPC build rather than deriving. FPC, measured:

    IncMonth(2026-01-31,  1) = 2026-02-28    { clamped }
    IncMonth(2026-01-31,  2) = 2026-03-31    { NOT Feb28+1mo — see below }
    IncMonth(2024-01-31,  1) = 2024-02-29    { leap }
    IncMonth(2026-03-31, -1) = 2026-02-28
    IncMonth(2026-12-31,  1) = 2027-01-31

  The second line is the one an implementation gets wrong: the clamp applies to
  the ORIGINAL day against the FINAL month, so it never compounds. Adding two
  months to the 31st lands on the 31st, not on the 28th that adding one month at
  a time would give. The time-of-day fraction is preserved. }
function IncMonth(const DateTime: TDateTime; NumberOfMonths: Integer): TDateTime;

{ FPC-style date/time formatting, the subset real code uses (Synapse's RFC-822
  / ISO-8601 / message-id renderers are the driving consumers): tokens
  yyyy yy mm m dd d hh h nn n ss s zzz z (case-insensitive), "..." and '...'
  quoted literals, everything else copied through. AM/PM and locale-name
  tokens (mmm/ddd) are NOT implemented — extend when a consumer needs them. }
function FormatDateTime(const Fmt: string; DateTime: TDateTime): string;

{ Parse "hh[:nn[:ss[.zzz]]]" (TimeSeparator-separated) into a time-of-day
  fraction. Raises EConvertError on malformed input. The fraction after the
  DecimalSeparator is a MILLISECOND FIELD, not a decimal fraction — '.25' is
  25 ms — and is accepted only after a full h:m:s; see the implementation.
  No AM/PM — extend on demand. }
function StrToTime(const S: string): TDateTime;

{ The parse direction of the date surface, mirroring the format direction
  (FormatDateTime / EncodeDate). Field ORDER comes from ShortDateFormat and the
  separator from DateSeparator, so ISO input is NOT universally valid: with the
  d/m/y default, StrToDate('2026-08-14') raises, exactly as FPC does — it reads
  2026 as the day. Measured against FPC 3.2.2, including:

  - one field is the DAY (current month and year), two are day+month (current
    year), three follow ShortDateFormat, four raise;
  - a year written with one or two digits goes through
    TwoDigitYearCenturyWindow, so '49' is 2049 and '99' is 1999 (the pivot
    moves with the current year — it is a sliding window, not a fixed century);
  - StrToDate REJECTS a trailing time, and StrToDateTime accepts either half
    alone;
  - the two failure classes carry different messages, and callers do match on
    them: a shape that does not scan is `"%s" is not a valid date format`,
    while fields that scan but do not exist (month 13, 29 Feb 2026) are the
    unquoted `Invalid date`.

  The TryStrTo* arms share one parser with the raising arms rather than
  duplicating it — the split between those two is where this family keeps
  going wrong ([[feature-lib-sysutils-strtodate-and-strtodatetime]]). }
function StrToDate(const S: string): TDateTime;
function StrToDateTime(const S: string): TDateTime;
function TryStrToDate(const S: string; var Value: TDateTime): Boolean;
function TryStrToTime(const S: string; var Value: TDateTime): Boolean;
function TryStrToDateTime(const S: string; var Value: TDateTime): Boolean;

{ Wall-clock now as a TDateTime (CLOCK_REALTIME via the PAL; UTC — this RTL
  has no timezone database, matching its POSIX/C fixed-locale stance). }
function Now: TDateTime;
function Date: TDateTime;
function Time: TDateTime;

function DateTimeToTimeStamp(DateTime: TDateTime): TTimeStamp;

{ ---- the render direction of the date surface (FPC SysUtils) ----
  FPC defines these as FormatDateTime with the shorthand format letters, and
  each letter expands to a FORMAT SETTING, not to a fixed layout:

    DateToStr     = 'ddddd' = ShortDateFormat
    TimeToStr     = 'tt'    = LongTimeFormat
    DateTimeToStr = 'c'     = ShortDateFormat, then — only when the time is
                              NON-ZERO — ' ' + LongTimeFormat
    DateTimeToStr(d, True) = 'f' = both halves, unconditionally

  So DateToStr on the C-locale defaults is '7-3-20', not an ISO date: '/' in a
  format string means DateSeparator (which defaults to '-'), and a lone 'y' is
  a TWO-digit year. Measured against FPC 3.2.2, not assumed.

  The zero-time rule is the one that surprises: DateTimeToStr of a pure date
  silently drops the time half, so a log line that usually reads
  '7-3-20 13:05:09' becomes '7-3-20' at exactly midnight. FPC tests only
  hour/minute/second — a non-zero MILLISECOND does not bring the time back. }
function DateToStr(Date: TDateTime): string;
function TimeToStr(Time: TDateTime): string;
function DateTimeToStr(DateTime: TDateTime): string;
function DateTimeToStr(DateTime: TDateTime; ForceTimeIfZero: Boolean): string;

{ Milliseconds since an unspecified origin, from the MONOTONIC clock — it does
  not jump when the wall clock is set, which is the whole reason timeout loops
  use it. FPC's GetTickCount is the deprecated 32-bit truncation of the same
  counter, and wraps every ~49 days; it is here because old code names it. }
function GetTickCount64: Int64;
function GetTickCount: LongWord;

{ Last-modification time of an OPEN handle, as Unix epoch SECONDS, or -1 when
  the handle is not stat-able. Unix FPC returns st_mtime raw here — it is NOT
  a TDateTime and NOT the DOS-packed value the name suggests on other targets;
  FileDateToDateTime is the converter. }
{ Last-modification time of a file BY PATH, as Unix epoch SECONDS, and -1 when
  the path cannot be stat'd OR NAMES A DIRECTORY. The directory case is FPC's,
  read out of its source rather than assumed (rtl/unix/sysutils.pp: `if
  (fpstat(...)<0) or fpS_ISDIR(info.st_mode) then exit(-1)`), and it is a real
  observable: a caller that hands this a directory gets -1, not a timestamp.

  Int64 rather than LongInt to match FPC trunk, and because epoch seconds in a
  LongInt stop working in 2038 -- a narrowing assignment into a caller's
  Longint still compiles, which is what FPC's own comphook.pas:474 does. }
function FileAge(const FileName: string): Int64;

{ The converters between the epoch seconds above and TDateTime.

  UTC, DELIBERATELY, AND THAT IS A DIVERGENCE FROM FPC'S `FileDateToDateTime`
  worth stating: FPC's unix arm calls EpochToLocal and applies the local
  timezone, while ours does not -- it matches FPC's `FileDateToUniversal`
  instead. This unit has no timezone database, and `Now` and `GetLocalTime`
  already answer in UTC for that reason.

  THE PROPERTY REAL CODE DEPENDS ON IS INTERNAL CONSISTENCY, NOT THE OFFSET:
  `FileDateToDateTime(FileAge(f)) < Now` is the question people actually ask,
  and it is correct here precisely because both sides use the same clock.
  Applying a timezone to one and not the other is what would break it, so
  matching FPC on this one function would make the pair WRONG rather than
  compatible. When a timezone database arrives, both move together. }
function FileDateToDateTime(FileDate: Int64): TDateTime;
function DateTimeToFileDate(DateTime: TDateTime): Int64;

function FileGetDate(Handle: Integer): Integer;

{ ---- Directory traversal: FindFirst / FindNext / FindClose ---------------

  THE ATTRIBUTE WORD IS DOS'S, NOT UNIX'S, and every value below was read off
  FPC's filutilh.inc:177-189 rather than recalled -- faAnyFile is $1FF there,
  not the widely-quoted $3F.

  MEASURED, because the obvious claim about that is wrong: on unix the two
  values select THE SAME ENTRIES, in every arrangement probed against fpc
  itself. faNormal is never set by the unix attribute mapping below, and
  faSymLink is only ever set when the caller already asked for it -- which
  puts the bit in the filter either way. So $3F is not a silent filter here;
  it is simply a different number, and the reason to carry FPC's is that a
  caller may compare against faAnyFile rather than only pass it. }
const
  faReadOnly   = $00000001;
  faHidden     = $00000002;
  faSysFile    = $00000004;
  faVolumeId   = $00000008;
  faDirectory  = $00000010;
  faArchive    = $00000020;
  faNormal     = $00000080;
  faSymLink    = $00000400;
  faAnyFile    = $000001FF;

  { fpc sysunixh.inc:44. It is '*' on unix and '*.*' on DOS-descended targets,
    so code that concatenates it is portable and code that hardcodes '*' is
    not -- which is why FPC exports the constant at all. }
  AllFilesMask = '*';

type
  { fpc filutilh.inc:81. `Time` is Unix epoch SECONDS here, as it is on FPC's
    unix arm -- NOT a packed DOS timestamp -- so FileDateToDateTime converts it
    and the same UTC reasoning stated above applies unchanged.

    `Mode` is the raw st_mode and is unix-only in FPC too. It is carried
    because the DOS attribute word cannot express the permission bits, and a
    caller that wants them has nowhere else to look. }
  TRawByteSearchRec = record
    Time: Int64;
    Size: Int64;
    Attr: LongInt;
    Name: AnsiString;
    ExcludeAttr: LongInt;
    FindHandle: Pointer;
    Mode: Integer;
  end;
  TSearchRec = TRawByteSearchRec;

{ Open a search. `Path` is a directory path with a FILENAME MASK on the end
  (`IncludeTrailingPathDelimiter(dir) + AllFilesMask`); `*` and `?` are the
  only metacharacters, which is FPC's FNMatch exactly -- it has no character
  classes, so `[abc]` is three literal characters here as it is there.

  Returns 0 when something was found and NONZERO when nothing was, which is
  the opposite polarity from most of this unit and is FPC's.

  `.` AND `..` ARE RETURNED, and that is not an oversight -- FPC returns them
  and real code depends on it: fpc's own cfileutl.pas:287 asks for
  `faAnyFile or faDirectory` and then filters both names out by hand, which is
  only necessary because they arrive. A caller that does not want them must do
  the same.

  Attr is a permissive FILTER, not a requirement: an entry is returned when
  every attribute bit it HAS is also set in Attr (`(entry and not Attr) = 0`),
  so faAnyFile returns everything and faDirectory alone returns only plain
  directories. faArchive and faReadOnly are added to the filter unconditionally,
  as FPC does, because every unix entry carries faArchive and an unwritable one
  carries faReadOnly -- without that, the obvious call returns nothing at all.

  EVERY SUCCESSFUL SEARCH MUST BE CLOSED WITH FindClose, including one you stop
  reading early: the handle owns a directory fd and a heap record. }
function FindFirst(const Path: AnsiString; Attr: LongInt; out Rslt: TRawByteSearchRec): LongInt;
{ Next match, same 0-is-found polarity. Safe to call after a failure: it stays
  failed rather than rewinding. }
function FindNext(var Rslt: TRawByteSearchRec): LongInt;
{ Release the search. Idempotent, and safe on a FindFirst that failed. }
procedure FindClose(var Rslt: TRawByteSearchRec);

{ The process environment, FPC's spelling. Read from /proc/self/environ, whose
  records are NUL-separated `NAME=VALUE` pairs — Linux-only, and deliberately so
  for now: the environment block sits on the initial stack, but reaching it
  needs a per-target intrinsic that does not exist yet (the route is written up
  in feature-rtl-environment-variables, and it can replace the reader later
  without changing this surface). An unset variable reads as '', as in FPC. }
function GetEnvironmentVariable(const Name: string): string;
function GetEnvironmentVariableCount: Integer;
{ The parent's environment as execve's `envp`, for handing to a spawned child.
  Call it in the parent, before vfork — see the body. }
function EnvironmentBlock: Pointer;

type
  { fpc osutilsh.inc:16 verbatim: `Set of ( ExecInheritsHandles)`. One member IS
    the whole type there, and `Flags: TExecuteFlags = []` in a caller's
    signature is all the corpus asks of it. }
  TExecuteFlags = set of (ExecInheritsHandles);

{ Spawn a program, wait for it, return its exit code — fpc osutilsh.inc:34-35.

  TWO OVERLOADS BECAUSE FPC HAS TWO, AND THEY DIFFER IN A WAY THAT MATTERS. The
  array form hands argv straight through. The string form SPLITS on whitespace
  and is quote-naive — deliberately, because fpc's is: cfileutl.pas:142 marks
  `ExecuteProcess = 'Do not use' deprecated 'ExecuteProcess cannot deal with
  single quotes as used by Unix command lines'`, which is FPC documenting this
  exact limitation in its own compiler. Matching a splitter nobody should rely
  on is not worth a quoting engine; a program that needs quoting passes the
  array form, which is what the deprecation tells it to do.

  RAISES EOSError on a failed spawn and on exit code 127, as fpc does. 127 is
  the child's way of reporting a failed exec — it is already a different
  process by then and cannot return a value — so a real program exiting 127 is
  indistinguishable from a missing binary. FPC has the same ambiguity and
  raises on both; matching the value is the whole compatibility test.

  `Flags` is accepted and NOT CONSULTED. PalVforkAndExec skips any fd given as
  -1 and this passes four, so the child inherits every handle already — which
  is exactly what ExecInheritsHandles asks for. Written down rather than left
  for a reader to infer from silence.
  feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags }
function ExecuteProcess(const Path: AnsiString; const ComLine: AnsiString;
                        Flags: TExecuteFlags = []): Integer;
function ExecuteProcess(const Path: AnsiString; const ComLine: array of AnsiString;
                        Flags: TExecuteFlags = []): Integer;

{ Write side (decide-env-write-side, user 2026-08-01: option 3). The write goes
  to OUR buffer — the same one GetEnvironmentVariable reads and the same one
  EnvironmentBlock hands to execve — so a value set here is visible both to this
  process and to any child spawned afterwards. That pairing is the decision's
  whole point: a process-local write ALONE would silently get the set-then-spawn
  case wrong, which this project treats as worse than not supporting writes.

  It does not reach an already-running child, and it does not touch
  /proc/self/environ — that is a read-only view of what the kernel handed us at
  exec time. Setting an existing name replaces it; an empty name is ignored. }
procedure SetEnvironmentVariable(const name, value: string);
procedure UnsetEnvironmentVariable(const name: string);
function GetEnvironmentString(Index: Integer): string;

{ File predicates over the PAL (FPC SysUtils). FileExists is True only for
  non-directories, DirectoryExists only for directories, matching FPC. }
function FileExists(const FileName: string): Boolean;
function DirectoryExists(const Dir: string): Boolean;
function DeleteFile(const FileName: string): Boolean;

{ ---- directory manipulation (FPC SysUtils) ----
  Boolean-returning, never raising — a failure is False, exactly as FPC's unix
  implementation returns `syscall = 0`. Measured against FPC 3.2.2:

  - CreateDir on an EXISTING directory is False (EEXIST is still a failure), so
    `if not CreateDir(d) then` is not the same question as "does d exist".
    ForceDirectories is the idempotent one — it is True when the path already
    exists, and it creates missing parents.
  - RemoveDir only removes an EMPTY directory (rmdir, not rm -r).
  - GetCurrentDir has no trailing slash ('/tmp', not '/tmp/'); ExpandFileName
    of the EMPTY string, by contrast, is cwd WITH one ('/tmp/'). Both measured.
  - RenameFile is rename(2): it fails across filesystems rather than copying. }
function CreateDir(const NewDir: string): Boolean;
function RemoveDir(const Dir: string): Boolean;
function ForceDirectories(const Dir: string): Boolean;
function GetCurrentDir: string;
function SetCurrentDir(const NewDir: string): Boolean;
function RenameFile(const OldName, NewName: string): Boolean;

{ ---- The path-separator constants and GetDir -----------------------------

  PLACEMENT DIVERGES FROM FPC ON PURPOSE, AND IT IS A REAL DIVERGENCE, not a
  detail: fpc declares all four of these in SYSTEM (systemh.inc:1509,
  sysunixh.inc:31-36), so they are visible with no `uses` at all. pxx's System
  is `compiler/builtin/builtin.pas`, which states in its own header that it
  contains no syscalls -- and GetDir is getcwd. Putting it there would mean
  layering the PAL into the one unit that documents having none, and it would
  be INERT until the next pin besides, because the pinned compiler resolves
  builtin from its OWN snapshot while resolving lib/rtl from the live tree.

  So it lives here, where the machinery already is, and the cost is stated
  rather than hidden: `GetDir(0, s)` in a program that does not use SysUtils
  compiles under fpc and does not compile here. Every caller that has turned up
  so far does filesystem work and already uses SysUtils -- fpc's own
  cfileutl.pas among them -- so nothing real is blocked, but a program CAN
  reach it. Moving them to System is a separate, pin-gated change. }
const
  { fpc sysunixh.inc:31. }
  DirectorySeparator = '/';
  { fpc sysunixh.inc:35, and the surprise is deliberate: BACKSLASH IS IN THIS
    SET ON UNIX. fpc accepts either byte as a separator when TESTING a path
    (this set is what `path_absolute` asks), while only ever WRITING '/'. A
    reimplementation that "corrects" it to ['/'] silently changes how every
    caller classifies a Windows-shaped path. }
  AllowDirectorySeparators: set of Char = ['\', '/'];
  { fpc sysunixh.inc:36. Empty on unix -- there are no drive letters. Carried
    rather than omitted because callers TEST it, and an absent constant is a
    compile error where an empty set is the correct answer. }
  AllowDriveSeparators: set of Char = [];

  { THE REST OF FPC'S sysunixh.inc:29-47 CONST BLOCK, added as one group rather
    than one at a time. DriveSeparator was NOT in the first version of this
    change -- only the two names the corpus wall happened to sit on -- and the
    corpus promptly produced it as the next head 178 lines further down the
    same file. One block in fpc's source is one group here; splitting it means
    re-measuring the whole corpus for a one-line constant.

    DRIVESEPARATOR IS AN EMPTY STRING ON UNIX, not a character. `Pos(DriveSeparator, s)`
    is real fpc code (cfileutl.pas:696) and answers 0, which is how a
    drive-letter scan is made to find nothing on a platform without drives. }
  DriveSeparator = '';
  ExtensionSeparator = '.';
  PathSeparator = ':';
  LFNSupport = True;
  maxExitCode = 255;
  { 4096 on Linux specifically -- the BSDs are 1024 in the same file. The value
    tracks the KERNEL, so it is not a portable constant to reuse elsewhere. }
  MaxPathLen = 4096;
  UnusedHandle = -1;

{ fpc sysunixh.inc:52-53. Typed constants, not `const`: fpc lets a program
  ASSIGN to these to describe a mounted filesystem that differs from the
  platform default, so they are writable here too. }
const
  FileNameCaseSensitive: Boolean = True;
  FileNameCasePreserving: Boolean = True;

{ fpc systemh.inc:1515. The current directory, WITHOUT a trailing separator
  (measured against fpc, not assumed). `DriveNr` is accepted and IGNORED, as it
  is on every fpc unix target -- it exists for DOS-descended ones. }
procedure GetDir(DriveNr: Byte; var Dir: AnsiString);

{ Absolute, '.'/'..'-collapsed form of FileName, relative to the CURRENT
  directory. Purely lexical after the cwd prefix — it does not stat anything and
  does not resolve symlinks, which is what FPC does too (measured:
  ExpandFileName('/a/./b/../c') = '/a/c' for paths that do not exist). A
  trailing slash on the input is PRESERVED. }
function ExpandFileName(const FileName: string): string;

{ Temp-file naming (FPC SysUtils; Synapse's GetTempFile). No TMPDIR probe --
  this RTL has no env access yet; '/tmp/' is the POSIX default. The name is
  unique against FileExists at pick time (same guarantee FPC gives). }
function GetTempDir: string;
function GetTempFileName(const Dir, Prefix: string): string;


type
  TTextLineBreakStyle = (tlbsLF, tlbsCRLF, tlbsCR);

{ Normalize every CR / LF / CRLF run to the requested break style (FPC
  SysUtils; Synapse's httpsend headers use tlbsCRLF). The 1-arg form uses the
  platform default — LF on this POSIX-only RTL. }
function AdjustLineBreaks(const S: AnsiString): AnsiString;
function AdjustLineBreaks(const S: AnsiString; Style: TTextLineBreakStyle): AnsiString;

{ System.SetString (FPC): size S to Len and copy Len chars from Buf (when
  non-nil). Lives here until the compiler grows it as a builtin. }
procedure SetString(var S: AnsiString; Buf: PChar; Len: Integer);
{ ^ RESTORED HERE 2026-09-11 as a deliberate duplicate of the copy in
  compiler/builtin/builtin.pas, because a $(PXX_STABLE) build sees the FROZEN
  builtin and cannot reach the moved name. The full note on sLineBreak carries
  the measurement and the retirement test. }

implementation

function StringOfChar(ch: Char; count: Integer): AnsiString;
var s: AnsiString; i: Integer;
begin
  s := '';
  for i := 1 to count do s := s + ch;
  Result := s;
end;

function AllocMem(Size: PtrUInt): Pointer;
begin
  Result := GetMem(Size);
  if (Result <> nil) and (Size > 0) then FillChar(Result^, Size, 0);
end;

uses platform, platform_types, wideint, strings, decfloat;

procedure FreeAndNil(var Obj);
var
  tmp: TObject;
  ref: ^Pointer;
begin
  ref := @Obj;
  tmp := TObject(ref^);
  ref^ := nil;          { nil FIRST, then free -- FPC's order, so a re-entrant destructor
                          cannot see a dangling reference }
  if tmp <> nil then tmp.Free;
end;

function StrLen(P: PChar): Integer;
var n: Integer;
begin
  n := 0;
  if P <> nil then
    while P[n] <> #0 do Inc(n);
  Result := n;
end;

function StrPas(P: PChar): AnsiString;
var i, n: Integer;
begin
  Result := '';
  if P = nil then Exit;
  n := StrLen(P);
  SetLength(Result, n);
  for i := 0 to n - 1 do
    Result[i + 1] := P[i];
end;

function sLineBreak: AnsiString;
begin
  Result := LineEnding;
end;

function StrToBoolDef(const s: AnsiString; def: Boolean): Boolean;
var t: AnsiString; f: Double;
begin
  { FPC TryStrToBool: the boolean WORDS, else ANY numeric string — a nonzero
    value (float included: '1.2') is True. fcl-json's TJSONString.AsBoolean
    depends on the float branch. }
  t := LowerCase(Trim(s));
  if t = 'true' then Result := True
  else if t = 'false' then Result := False
  else if TryStrToFloat(t, f) then Result := (f <> 0)
  else Result := def;
end;

function StrToBool(const s: AnsiString): Boolean;
var t: AnsiString; f: Double;
begin
  { FPC parity: raises EConvertError on a string that is neither a boolean
    word nor numeric (this RTL used to return False silently). }
  t := LowerCase(Trim(s));
  if t = 'true' then Result := True
  else if t = 'false' then Result := False
  else if TryStrToFloat(t, f) then Result := (f <> 0)
  else raise EConvertError.CreateFmt('"%s" is not a valid boolean', [s]);
end;

{ Both bodies are a bare assignment ON PURPOSE -- see the declaration. The store carries the
  width conversion when the widths differ and is a plain copy when they do not, so there is one
  transcoder in this compiler and it lives in the runtime, not here. }
function UTF8Decode(const s: AnsiString): UnicodeString;
begin
  Result := s;
end;

function UTF8Encode(const s: UnicodeString): AnsiString;
begin
  Result := s;
end;

{ The sentinel trick these three share: parse with two DIFFERENT defaults. A malformed input
  yields whichever default was asked for, so the two runs disagree; a well-formed input parses
  to the same value both times. That is cheaper and more honest than duplicating each
  parser's validation, and it cannot be fooled -- no single input can equal both sentinels. }
{ ZERO on failure. FPC's documentation calls the value undefined after a failed
  Val, so leaving it alone was not strictly wrong — but FPC in practice zeroes
  it, and a stale value surviving a failed conversion is the shape that bites:
  `if not TryStrToInt(s, n) then` is usually followed by code that uses `n`
  with a default in mind, and it silently got the caller's own previous value.
  Switching the declarations to `out` would NOT do it — pxx does not model
  `out` (bug-a-an-out-parameter-of-a-managed-type-is-not-cleared) and FPC's
  `out` does not clear ordinals either. One explicit assignment each.
  bug-b-sysutils-string-gaps-found-by-differential }
function TryStrToInt64(const s: AnsiString; var value: Int64): Boolean;
begin
  Result := ParseIntPrefixed(s, value);
  if not Result then value := 0;
end;

function TryStrToQWord(const s: AnsiString; var value: QWord): Boolean;
var a, b: QWord;
begin
  a := StrToQWordDef(s, 0);
  b := StrToQWordDef(s, 1);
  Result := (a = b);
  if Result then value := a else value := 0;   { see TryStrToInt64 }
end;

{ ParseFloatCore, the single float parser the whole StrToFloat family wraps,
  lives in lib/rtl/decfloat.pas with the exact-decimal machinery it uses, so
  that builtin's Val reaches the same routine. }

function TryStrToFloat(const s: AnsiString; var value: Double): Boolean;
begin
  { One parse. This used to call StrToFloatDef TWICE -- once defaulting to 0.0,
    once to 1.0 -- and compare the answers, using disagreement as the failure
    signal because the parser had no other way to report it. That cost a full
    second parse on EVERY call, and StrToFloat goes through here, so the whole
    family paid it: measured at 1.9-2.0x on every shape from the fast path to a
    subnormal ([[bug-b-strtofloat-is-3600x-slower-than-cpython-for-small-exponents]]).
    ParseFloatCore returns the flag directly, so the trick is not needed. }
  Result := ParseFloatCore(s, value);
  if not Result then value := 0.0;             { see TryStrToInt64 }
end;

constructor Exception.Create(const msg: string);
begin
  FMessage := msg;
  FHelpContext := 0;
end;

function StrToInt64(const s: AnsiString): Int64;
begin
  { FPC parity: raises EConvertError on malformed input (used to return 0). }
  if not TryStrToInt64(s, Result) then
    raise EConvertError.CreateFmt('"%s" is an invalid integer', [s]);
end;

function StrToQWordDef(const s: AnsiString; def: QWord): QWord;
var
  i, n: Integer;
  v: QWord;
  any: Boolean;
begin
  Result := def;
  n := Length(s);
  i := 1;
  while (i <= n) and (s[i] = ' ') do Inc(i);
  if (i <= n) and (s[i] = '+') then Inc(i);   { unsigned: no '-' }
  v := 0;
  any := False;
  while i <= n do
  begin
    if (s[i] < '0') or (s[i] > '9') then Exit;   { malformed -> def }
    v := v * 10 + QWord(Ord(s[i]) - Ord('0'));
    any := True;
    Inc(i);
  end;
  if any then Result := v;
end;

function StrToQWord(const s: AnsiString): QWord;
begin
  { FPC parity: raises EConvertError on malformed input (used to return 0). }
  if not TryStrToQWord(s, Result) then
    raise EConvertError.CreateFmt('"%s" is an invalid QWord', [s]);
end;

function HexStr(Value: Int64; Digits: Integer): AnsiString;
begin
  Result := IntToHex(Value, Digits);
end;


constructor Exception.CreateFmt(const msg: string; const args: array of const);
begin
  FMessage := Format(msg, args);
  FHelpContext := 0;
end;

{ Dereference and construct — see the declaration for why that is the whole
  implementation and why the name promises more. A nil pointer yields an empty
  message rather than a fault: these are raised on an error path, and a crash
  inside the reporting of an error destroys the information the error carried. }
constructor Exception.CreateRes(ResString: PResStringRec);
begin
  if ResString = nil then FMessage := ''
  else FMessage := ResString^;
  FHelpContext := 0;
end;

constructor Exception.CreateResFmt(ResString: PResStringRec; const args: array of const);
begin
  if ResString = nil then FMessage := ''
  else FMessage := Format(ResString^, args);
  FHelpContext := 0;
end;

{ The TRuntimeError -> our-exception mapping. See the declaration: raising is
  faithful in effect, the numbers are deliberately ours. }
procedure OutOfMemoryError;
begin
  raise EOutOfMemory.Create('Out of memory');
end;

procedure Error(RuntimeError: TRuntimeError);
begin
  case RuntimeError of
    reNone:              Exit;
    reOutOfMemory:       raise EOutOfMemory.Create('Out of memory');
    reInvalidPtr:        raise EInvalidPointer.Create('Invalid pointer operation');
    reDivByZero:         raise EDivByZero.Create('Division by zero');
    reRangeError:        raise ERangeError.Create('Range check error');
    reIntOverflow:       raise EIntOverflow.Create('Arithmetic overflow');
    reInvalidOp:         raise EInvalidOp.Create('Invalid floating point operation');
    reZeroDivide:        raise EZeroDivide.Create('Floating point division by zero');
    reOverflow:          raise EOverflow.Create('Floating point overflow');
    reUnderflow:         raise EUnderflow.Create('Floating point underflow');
    reInvalidCast:       raise EInvalidCast.Create('Invalid type cast');
    reAccessViolation:   raise EAccessViolation.Create('Access violation');
    reStackOverflow:     raise EOutOfMemory.Create('Stack overflow');
    reVarTypeCast:       raise EVariantError.Create('Invalid variant type cast');
    reVarInvalidOp:      raise EVariantError.Create('Invalid variant operation');
    reVarDispatch:       raise EVariantError.Create('Variant dispatch error');
    reVarArrayCreate:    raise EVariantError.Create('Variant array creation error');
    reVarNotArray:       raise EVariantError.Create('Variant is not an array');
    reVarArrayBounds:    raise EVariantError.Create('Variant array bounds error');
    reAssertionFailed:   raise EAssertionFailed.Create('Assertion failed');
    reIntfCastError:     raise EInvalidCast.Create('Interface cast error');
  else
    { rePrivInstruction, reControlBreak, reExternalException, reSafeCallError,
      reQuit, reCodesetConversion, reNoDynLibsSupport, reThreadError — no closer
      class here. Naming the member beats a bare halt, and beats mapping it to a
      class that would then be caught by a handler that did not mean it. }
    raise Exception.Create('Runtime error ' +
      IntToStr(Ord(RuntimeError)) + ' (TRuntimeError)');
  end;
end;
{ The unsigned digit loop, and the only one in this unit. `div`/`mod` by 10
  are UNSIGNED here because the operand type is QWord, which is exactly what the
  signed body could not do for a value with the top bit set. }
function UIntToStr(value: QWord): AnsiString;
var s: AnsiString; d: QWord;
begin
  if value = 0 then
  begin
    Result := '0';
    Exit;
  end;
  s := '';
  while value > 0 do
  begin
    d := value mod 10;
    s := Chr(Ord('0') + Integer(d)) + s;
    value := value div 10;
  end;
  Result := s;
end;

{ Cardinal widens into the QWord loop losslessly; declared so FPC source that
  spells the 32-bit call explicitly compiles unchanged. }
function UIntToStr(value: Cardinal): AnsiString;
begin
  Result := UIntToStr(QWord(value));
end;

function IntToStr(value: QWord): AnsiString;
begin
  Result := UIntToStr(value);
end;

function IntToStr(value: Int64): AnsiString;
var s: AnsiString; neg: Boolean; d: Int64;
begin
  if value = 0 then
  begin
    Result := '0';
    Exit;
  end;
  neg := value < 0;
  s := '';
  if neg then
  begin
    { Digits are accumulated on the NEGATIVE side, because Low(Int64) has no
      positive counterpart: `value := -value` leaves it unchanged (still
      negative), the `while value > 0` loop then never runs, and IntToStr
      returned a bare '-'. Every value in range is representable as a negative,
      so this direction has no special case. `mod` of a negative is <= 0 here
      (truncated division, same as FPC), hence the unary minus on d. }
    while value <> 0 do
    begin
      d := -(value mod 10);
      s := Chr(Ord('0') + Integer(d)) + s;
      value := value div 10;
    end;
    s := '-' + s;
  end
  else
    while value > 0 do
    begin
      d := value mod 10;
      s := Chr(Ord('0') + Integer(d)) + s;
      value := value div 10;
    end;
  Result := s;
end;

function IntToHex(value: Int64; digits: Integer): AnsiString;
var s: AnsiString; u: UInt64; nib: Integer; c: Char;
begin
  u := UInt64(value);
  if u = 0 then
    s := '0'
  else
  begin
    s := '';
    while u > 0 do
    begin
      nib := Integer(u and 15);
      if nib < 10 then c := Chr(Ord('0') + nib)
      else c := Chr(Ord('A') + nib - 10);
      s := c + s;
      u := u shr 4;
    end;
  end;
  while Length(s) < digits do s := '0' + s;
  Result := s;
end;

{ 32-bit signed: mask to its own 32 bits FIRST, so a negative renders eight
  digits and not sixteen. LongWord() is the mask; the Int64 widening after it
  is then zero-extension. }
function IntToHex(value: LongInt; digits: Integer): AnsiString;
begin
  Result := IntToHex(Int64(LongWord(value)), digits);
end;

{ 32-bit unsigned: no sign to extend, but declared so a Cardinal/Word/Byte
  argument cannot pick up the Int64 spelling by widening. }
function IntToHex(value: LongWord; digits: Integer): AnsiString;
begin
  Result := IntToHex(Int64(value), digits);
end;

function Copy(const s: AnsiString; index, count: Integer): AnsiString;
var n, last, len: Integer;
begin
  n := Length(s);
  if index < 1 then index := 1;
  if count < 0 then count := 0;
  { cap count BEFORE forming last: Copy(s, i, MaxInt) overflowed to '' }
  if count > n - index + 1 then count := n - index + 1;
  last := index + count - 1;
  len := last - index + 1;
  if len <= 0 then begin Result := ''; Exit; end;
  { build the result once — SetLength + a single Move, not char-by-char append }
  SetLength(Result, len);
  Move(s[index], Result[1], len);
end;

function Copy(const s: AnsiString; index: Integer): AnsiString;
begin
  Result := Copy(s, index, Length(s));
end;

function CharInSet(Ch: AnsiChar; const CSet: TSysCharSet): Boolean;
begin
  CharInSet := Ch in CSet;
end;

function AnsiDequotedStr(const S: AnsiString; AQuote: Char): AnsiString;
var i, n: Integer;
begin
  AnsiDequotedStr := '';
  n := Length(S);
  if n = 0 then Exit;
  { Not quoted at all: FPC returns the whole string WITHOUT scanning it. }
  if S[1] <> AQuote then
  begin
    AnsiDequotedStr := S;
    Exit;
  end;
  i := 2;
  while i <= n do
  begin
    if S[i] = AQuote then
    begin
      { A doubled quote is one literal quote; a lone one closes the string. }
      if (i < n) and (S[i + 1] = AQuote) then
      begin
        AnsiDequotedStr := AnsiDequotedStr + AQuote;
        i := i + 2;
        Continue;
      end;
      Exit;
    end;
    AnsiDequotedStr := AnsiDequotedStr + S[i];
    i := i + 1;
  end;
  { Fell off the end: an unterminated quote keeps everything after it. }
end;

function Trim(const s: AnsiString): AnsiString;
var a, b: Integer;
begin
  a := 1;
  b := Length(s);
  while (a <= b) and (s[a] <= ' ') do a := a + 1;
  while (b >= a) and (s[b] <= ' ') do b := b - 1;
  Result := Copy(s, a, b - a + 1);
end;

{ THE integer parser. Everything that turns text into an integer goes through
  here -- StrToIntDef, StrToInt64Def, TryStrToInt, TryStrToInt64 -- because when
  they were four separate implementations they disagreed with EACH OTHER, never
  mind with FPC: TryStrToInt('42 ') accepted a trailing space that
  StrToIntDef('42 ') rejected, and none of the four saw a radix prefix. FPC
  funnels all four through one Val and its four answers agree for every input;
  that structure is the fix, not just the individual behaviours.

  Accepts, per FPC: leading spaces but NOT trailing, an optional sign BEFORE the
  radix prefix ('-$FF'), and the prefixes '$' / '0x' / '0X' hex, '&' octal, '%'
  binary; otherwise decimal. A digit outside the base ('&19', '%12') is
  rejected, as is a prefix with no digits after it ('$', '0x').

  Digits accumulate NEGATIVE so Low(Int64) -- which has no positive counterpart
  -- is reachable without the accumulator ever holding an unrepresentable value,
  which is what makes the overflow test exact at both ends. }
function ParseIntPrefixed(const s: AnsiString; var v: Int64): Boolean;
var i, base, digit: Integer; c: Char; neg, started: Boolean;
begin
  ParseIntPrefixed := False;
  v := 0; neg := False; started := False; i := 1;
  while (i <= Length(s)) and (s[i] = ' ') do i := i + 1;
  if (i <= Length(s)) and ((s[i] = '-') or (s[i] = '+')) then
  begin
    neg := s[i] = '-';
    i := i + 1;
  end;
  base := 10;
  if i <= Length(s) then
  begin
    if s[i] = '$' then begin base := 16; i := i + 1; end
    else if s[i] = '&' then begin base := 8; i := i + 1; end
    else if s[i] = '%' then begin base := 2; i := i + 1; end
    else if (s[i] = '0') and (i < Length(s)) and ((s[i + 1] = 'x') or (s[i + 1] = 'X')) then
    begin base := 16; i := i + 2; end;
  end;
  while i <= Length(s) do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') then digit := Ord(c) - Ord('0')
    else if (c >= 'a') and (c <= 'f') then digit := Ord(c) - Ord('a') + 10
    else if (c >= 'A') and (c <= 'F') then digit := Ord(c) - Ord('A') + 10
    else Exit;
    if digit >= base then Exit;
    { split in two so neither test can itself overflow }
    if v < Low(Int64) div base then Exit;
    v := v * base;
    if v < Low(Int64) + digit then Exit;
    v := v - digit;
    started := True;
    i := i + 1;
  end;
  if not started then Exit;
  if not neg then
  begin
    { |Low(Int64)| is one past High(Int64), so it has no positive form }
    if v = Low(Int64) then Exit;
    v := -v;
  end;
  ParseIntPrefixed := True;
end;

{ 32-bit overflow TRUNCATES rather than failing: FPC's StrToIntDef('99999999999')
  is 1215752191, not the default. Only a value too large for Int64 is rejected. }
function StrToIntDef(const s: AnsiString; def: Integer): Integer;
var v: Int64;
begin
  if ParseIntPrefixed(s, v) then Result := Integer(v) else Result := def;
end;

function StrToInt(const s: AnsiString): Integer;
begin
  { FPC parity: raises EConvertError on malformed input (used to return 0). }
  if not TryStrToInt(s, Result) then
    raise EConvertError.CreateFmt('"%s" is an invalid integer', [s]);
end;

function StrToInt64Def(const s: AnsiString; def: Int64): Int64;
var v: Int64;
begin
  if ParseIntPrefixed(s, v) then Result := v else Result := def;
end;

function LastDelimiter(const Delimiters, S: AnsiString): Integer;
var i, j: Integer;
begin
  for i := Length(S) downto 1 do
    for j := 1 to Length(Delimiters) do
      if S[i] = Delimiters[j] then
      begin
        Result := i;
        Exit;
      end;
  Result := 0;
end;

function UpCase(const s: AnsiString): AnsiString;
var i: Integer;
begin
  Result := s;
  for i := 1 to Length(Result) do
    Result[i] := UpCase(Result[i]);
end;

function UpCase(c: Char): Char;
begin
  if (c >= 'a') and (c <= 'z') then
    Result := Chr(Ord(c) - 32)
  else
    Result := c;
end;
function StrLCopy(Dest, Source: PChar; MaxLen: Cardinal): PChar;
var i: Cardinal;
begin
  Result := Dest;
  i := 0;
  while (i < MaxLen) and (Source[i] <> #0) do
  begin
    Dest[i] := Source[i];
    Inc(i);
  end;
  Dest[i] := #0;
end;

function StrLComp(Str1, Str2: PChar; MaxLen: Cardinal): Integer;
var i: Cardinal; c1, c2: Integer;
begin
  Result := 0;
  i := 0;
  while i < MaxLen do
  begin
    c1 := Ord(Str1[i]);
    c2 := Ord(Str2[i]);
    if (c1 <> c2) or (c1 = 0) then
    begin
      Result := c1 - c2;
      Exit;
    end;
    Inc(i);
  end;
end;

{ ---- the PChar family, forwarded to `strings` ----
  Qualified calls on purpose: an unqualified StrCopy here would resolve to this
  very function and recurse. The contracts live in lib/rtl/strings.pas, measured
  against FPC there; nothing is re-derived in this file. }

function StrCopy(Dest, Source: PChar): PChar;
begin
  Result := strings.StrCopy(Dest, Source);
end;

function StrCat(Dest, Source: PChar): PChar;
begin
  Result := strings.StrCat(Dest, Source);
end;

function StrComp(Str1, Str2: PChar): Integer;
begin
  Result := strings.StrComp(Str1, Str2);
end;

function StrIComp(Str1, Str2: PChar): Integer;
begin
  Result := strings.StrIComp(Str1, Str2);
end;

function StrEnd(P: PChar): PChar;
begin
  Result := strings.StrEnd(P);
end;

function StrScan(P: PChar; C: Char): PChar;
begin
  Result := strings.StrScan(P, C);
end;

function StrRScan(P: PChar; C: Char): PChar;
begin
  Result := strings.StrRScan(P, C);
end;

function StrPos(Str1, Str2: PChar): PChar;
begin
  Result := strings.StrPos(Str1, Str2);
end;

function StrECopy(Dest, Source: PChar): PChar;
begin
  Result := strings.StrECopy(Dest, Source);
end;

function StrMove(Dest, Source: PChar; L: Integer): PChar;
begin
  Result := strings.StrMove(Dest, Source, L);
end;

function StrUpper(P: PChar): PChar;
begin
  Result := strings.StrUpper(P);
end;

function StrLower(P: PChar): PChar;
begin
  Result := strings.StrLower(P);
end;

function StrPCopy(Dest: PChar; const Source: AnsiString): PChar;
begin
  Result := strings.StrPCopy(Dest, Source);
end;

function StrPLCopy(Dest: PChar; const Source: AnsiString; MaxLen: Integer): PChar;
begin
  Result := strings.StrPLCopy(Dest, Source, MaxLen);
end;

function StrAlloc(Size: Integer): PChar;
begin
  Result := strings.StrAlloc(Size);
end;

function StrBufSize(Str: PChar): Integer;
begin
  Result := strings.StrBufSize(Str);
end;

function StrNew(P: PChar): PChar;
begin
  Result := strings.StrNew(P);
end;

procedure StrDispose(Str: PChar);
begin
  strings.StrDispose(Str);
end;

{ THROUGH THE PAL, which has owned this since it had a backend at all.

  This unit used to carry its own four-arm nanosleep NUMBER TABLE and spell
  __pxxrawsyscall itself. platform.pas already holds those numbers, per platform,
  with three maintained backends -- so the table here was a second name for one
  fact, and PalBackendNanosleep on posix issues the identical syscall with the
  identical timespec. Routing through it DELETES the duplicate rather than
  guarding it.

  WHAT THE -1 GUARD ACTUALLY WAS. `n := SysNanosleepNo; if n = -1 then Exit;`
  reads as a soft failure on a target with no number, and it is not: the guard is
  a RUNTIME test in front of an instruction that is still EMITTED, so a backend
  with no syscall lowering refuses the BODY. On wasm32 -- where wasi has imports
  and can never have syscall numbers -- that was `value IR op 54`, the whole body
  emitted as `unreachable`, and this one procedure gated 82 of the 200 corpus
  programs that reached the backend. PalNanosleep answers PAL_ERR_UNSUPPORTED
  there, which is the same defined failure the guard MEANT, decided at COMPILE
  time. Same shape frankb-78 fixed in pypal (bce31c210); the smaller move here is
  that the right call already exists.

  AND THE DUPLICATE HAD ALREADY SHIPPED A SILENT FAILURE, in this unit's sibling
  rather than here: ansiterm.pas's private copy was simply missing riscv32 and
  xtensa, GetSysWrite returned -1, AnsiWrite's `if w = -1 then Exit` took it, and
  every TUI drew NOTHING on two targets while WriteLn kept working
  (bug-b-ansiterm-has-no-syscall-numbers-for-riscv32-or-xtensa-so-every-tui-draws-nothing).
  The -1 guard that was supposed to be the safety net is what swallowed it. }
procedure Sleep(Milliseconds: Cardinal);
var ignored: Integer;
begin
  ignored := PalNanosleep(Milliseconds div 1000,
                          Int64(Milliseconds mod 1000) * 1000000);
  { THE SIBLING SPELLING OF A BLOCKING POINT, and it is the one a PASCAL program
    writes. `mimic_time.sleep` is what `time.sleep` binds to from NilPy and it
    pumps too; both mean "I am about to stop doing work" to whoever wrote the
    source, so wiring only one leaves the other permanently unpumped -- the
    normalise-dont-special-case sibling case, where the second path is the one
    that stays broken and no test corpus distinguishes them by name.

    MEASURED, NOT REASONED: the fixture for this feature wrote
    `uses interrupts, mimic_time, sysutils` and its bare `sleep(0)` bound HERE,
    to sysutils, because the last unit in a uses clause wins. The drain row read
    0 and looked like a broken pump. Had the two units been listed the other way
    round the same fixture would have passed and this gap would have shipped
    unseen -- which is exactly the arrangement-dependence CLAUDE.md warns about,
    arriving in a uses clause.
    feature-s-interrupt-events-reach-python-outside-interrupt-context }
  PalDrainPending;
end;

{ Move/FillChar bodies removed — now compiler builtins (see interface note). }

function UpperCase(const s: AnsiString): AnsiString;
var i: Integer; c: Char;
begin
  SetLength(Result, Length(s));        { size once, index-assign — not O(n^2) append }
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'a') and (c <= 'z') then c := Chr(Ord(c) - 32);
    Result[i] := c;
  end;
end;

function AnsiUpperCase(const s: AnsiString): AnsiString;
begin
  Result := UpperCase(s);
end;

function AnsiLowerCase(const s: AnsiString): AnsiString;
begin
  Result := LowerCase(s);
end;

function LowerCase(const s: AnsiString): AnsiString;
var i: Integer; c: Char;
begin
  SetLength(Result, Length(s));
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    Result[i] := c;
  end;
end;

function Pos(const substr, s: AnsiString; offset: Integer): Integer;
var i, j, m, n: Integer; match: Boolean;
begin
  Result := 0;
  m := Length(substr);
  n := Length(s);
  if (m = 0) or (offset < 1) or (offset > n) then Exit;
  for i := offset to n - m + 1 do
  begin
    match := True;
    for j := 1 to m do
      if s[i + j - 1] <> substr[j] then begin match := False; Break; end;
    if match then begin Result := i; Exit; end;
  end;
end;

function Pos(const substr, s: AnsiString): Integer;
var i, j, m, n: Integer; match: Boolean;
begin
  m := Length(substr);
  n := Length(s);
  { An empty needle is NOT found at position 1. That is C's strstr convention;
    Delphi and FPC both return 0, and PosEx here already did. Returning 1 makes
    the common `if Pos(sep, s) > 0` guard fire on an empty separator. }
  if m = 0 then begin Result := 0; Exit; end;
  for i := 1 to n - m + 1 do
  begin
    match := True;
    for j := 1 to m do
    begin
      if s[i + j - 1] <> substr[j] then
      begin
        match := False;
        Break;
      end;
    end;
    if match then begin Result := i; Exit; end;
  end;
  Result := 0;
end;

{ Decimal exponent form, for magnitudes the Int64 split below cannot hold.
  The mantissa is normalised into [1,10) and then formatted by FloatToStr
  itself, which is in-range by construction, so there is one formatting rule
  rather than two. }
function FloatToExpStr(value: Double): AnsiString;
var neg: Boolean; e: Integer; m: AnsiString;
begin
  neg := value < 0.0;
  if neg then value := -value;
  e := 0;
  while value >= 10.0 do begin value := value / 10.0; e := e + 1; end;
  while (value > 0.0) and (value < 1.0) do begin value := value * 10.0; e := e - 1; end;
  m := FloatToStr(value);
  if e >= 0 then Result := m + 'E+' + IntToStr(e)
  else Result := m + 'E-' + IntToStr(-e);
  if neg then Result := '-' + Result;
end;


{ Round an exact digit string to sig digits, half-to-EVEN on the exact
  remainder (glibc's %.*g rule — and the remainder here really is exact, so
  the tie case is a genuine tie rather than an artifact of scaling). A carry
  out of the leading digit (999 -> 100) moves the decimal exponent. }
procedure ExDecRound(var ds: AnsiString; var decExp: Integer; sig: Integer);
var i, c: Integer; up, rest: Boolean;
begin
  if Length(ds) <= sig then Exit;
  up := False;
  if ds[sig + 1] > '5' then up := True
  else if ds[sig + 1] = '5' then
  begin
    rest := False;
    for i := sig + 2 to Length(ds) do
      if ds[i] <> '0' then begin rest := True; break; end;
    if rest then up := True
    else up := ((Ord(ds[sig]) - Ord('0')) mod 2) = 1;
  end;
  ds := Copy(ds, 1, sig);
  if up then
  begin
    i := sig;
    while i >= 1 do
    begin
      c := Ord(ds[i]) - Ord('0') + 1;
      if c < 10 then begin ds[i] := Chr(Ord('0') + c); break; end;
      ds[i] := '0';
      i := i - 1;
    end;
    if i = 0 then
    begin
      ds := '1' + Copy(ds, 1, sig - 1);
      decExp := decExp + 1;
    end;
  end;
end;

{ FPC's ffGeneral layout: fixed while the point sits in [-3, sig], exponential
  otherwise. Shared with FloatToStrSig so both entry points format alike. }
function ExDecLayout(const ds: AnsiString; decExp, sig: Integer): AnsiString;
var p, i: Integer; s: AnsiString;
begin
  p := decExp + 1;
  if (p > sig) or (p < -3) then
  begin
    if Length(ds) > 1 then s := Copy(ds, 1, 1) + '.' + Copy(ds, 2, Length(ds) - 1)
    else s := ds;
    if p - 1 >= 0 then s := s + 'E' + IntToStr(p - 1)
    else s := s + 'E-' + IntToStr(1 - p);
  end
  else if p <= 0 then
  begin
    s := '0.';
    for i := 1 to -p do s := s + '0';
    s := s + ds;
  end
  else if p >= Length(ds) then
  begin
    s := ds;
    for i := Length(ds) + 1 to p do s := s + '0';
  end
  else
    s := Copy(ds, 1, p) + '.' + Copy(ds, p + 1, Length(ds) - p);
  Result := s;
end;

function FloatToStrExact(value: Double; sigDigits: Integer): AnsiString;
var ds: AnsiString; decExp, sig, i: Integer; neg: Boolean;
begin
  sig := sigDigits;
  if sig < 1 then sig := 1;
  { past the exact expansion there is nothing left to ask for }
  if sig > 767 then sig := 767;
  if value <> value then begin Result := 'NaN'; Exit; end;
  if value > 1.7976931348623157e308 then begin Result := 'Inf'; Exit; end;
  if value < -1.7976931348623157e308 then begin Result := '-Inf'; Exit; end;
  if value = 0.0 then begin Result := '0'; Exit; end;
  neg := value < 0.0;
  if neg then value := -value;
  ExDecDigits(value, ds, decExp);
  ExDecRound(ds, decExp, sig);
  { trailing zeros carry no information in either form }
  i := Length(ds);
  while (i > 1) and (ds[i] = '0') do i := i - 1;
  ds := Copy(ds, 1, i);
  Result := ExDecLayout(ds, decExp, sig);
  if neg then Result := '-' + Result;
end;

function FloatToStrShortest(value: Double): AnsiString;
var i: Integer; s: AnsiString;
begin
  { NaN / Inf / zero have one spelling each; FloatToStrExact already gives it }
  if (value <> value) or (value = 0.0)
     or (value > 1.7976931348623157e308) or (value < -1.7976931348623157e308) then
  begin
    Result := FloatToStrExact(value, 17);
    Exit;
  end;
  { 17 significant digits always round-trip a double, so this loop terminates
    with the shortest spelling that does. }
  for i := 1 to 16 do
  begin
    s := FloatToStrExact(value, i);
    if StrToFloat(s) = value then begin Result := s; Exit; end;
  end;
  Result := FloatToStrExact(value, 17);
end;

{ FPC's `FloatToStr` IS `FloatToStrF(value, ffGeneral, 15, 0)`: fifteen
  SIGNIFICANT digits, not a fixed number of decimal places, switching to
  exponential form when the decimal point falls outside the window
  [-3, 15]. The old implementation kept six DECIMAL places, which silently
  dropped nine digits from `1/3` and — far worse — returned the string `'0'`
  for every magnitude below 5e-7, because both the integer part and the
  rounded six-place fraction were zero. A nonzero number printing as zero is
  the value-LOSS half of that bug and the half worth fixing.

  Significant digits are counted off a normalised mantissa. Scaling by powers
  of ten costs a unit or two in the last place on awkward values; that is the
  representation half, which is explicitly not worth chasing here. }
{ FloatToStr is this with FPC's fifteen; Format's `%.Ng` asks for N. The
  fixed/exponential window is `[-3, sig]`, which is FPC's ffGeneral rule and
  therefore moves with the requested precision. }
function FloatToStrSig(value: Double; sigDigits: Integer): AnsiString;
var
  neg: Boolean;
  e10, p, i, k, sig: Integer;
  m, scaleLo, scaleHi: Double;
  p10: array[0..8] of Double;
  digits: Int64;
  ds, s: AnsiString;
begin
  sig := sigDigits;
  if sig < 1 then sig := 1;
  { Past 15 a double scaled in doubles lies, so hand those over to the exact
    expansion, which does not scale in doubles at all. Up to 15 this keeps its
    own long-standing output: FloatToStr is the shared Pascal path and its
    formatting is observable by every program and test expectation in the tree,
    so it is not changed here as a side effect of gaining 16 and 17. }
  if sig > 15 then begin Result := FloatToStrExact(value, sig); Exit; end;
  if value <> value then begin Result := 'NaN'; Exit; end;
  { Infinity first: the normalise loop below would not terminate on it. }
  if value > 1.7976931348623157e308 then begin Result := 'Inf'; Exit; end;
  if value < -1.7976931348623157e308 then begin Result := '-Inf'; Exit; end;
  if value = 0.0 then begin Result := '0'; Exit; end;
  neg := value < 0.0;
  if neg then value := -value;

  { Normalise into [1,10) and record the decimal exponent. Scaling one decade
    at a time would round up to 300 times on a denormal and lose the last
    digits outright (1e-300 came out as 9.99999999999999E-301); stepping by
    powers of two decades costs at most nine roundings for any finite double. }
  p10[0] := 1.0e1;   p10[1] := 1.0e2;   p10[2] := 1.0e4;   p10[3] := 1.0e8;
  p10[4] := 1.0e16;  p10[5] := 1.0e32;  p10[6] := 1.0e64;  p10[7] := 1.0e128;
  p10[8] := 1.0e256;
  m := value;
  e10 := 0;
  if m >= 10.0 then
  begin
    k := 256;
    for i := 8 downto 0 do
    begin
      if m >= p10[i] then begin m := m / p10[i]; e10 := e10 + k; end;
      k := k div 2;
    end;
  end
  else if m < 1.0 then
  begin
    { multiply up. `m * p10[i] < 10` keeps the mantissa from overshooting the
      window; the residual decade is settled by the loops below. }
    k := 256;
    for i := 8 downto 0 do
    begin
      if m * p10[i] < 10.0 then begin m := m * p10[i]; e10 := e10 - k; end;
      k := k div 2;
    end;
  end;
  { A scaled value can land a hair outside [1,10) — settle it exactly. }
  while m >= 10.0 do begin m := m / 10.0; e10 := e10 + 1; end;
  while m < 1.0 do begin m := m * 10.0; e10 := e10 - 1; end;

  { `sig` significant digits as an integer. Rounding can carry into the next
    power of ten (9.9999999999999999 -> 10), which is a shift, not a digit. }
  scaleLo := 1.0;
  for i := 2 to sig do scaleLo := scaleLo * 10.0;   { 10^(sig-1) }
  scaleHi := scaleLo * 10.0;                        { 10^sig     }
  digits := Round(m * scaleLo);
  if digits >= Round(scaleHi) then
  begin
    digits := digits div 10;
    e10 := e10 + 1;
  end;
  ds := IntToStr(digits);
  { trailing zeros carry no information in either form }
  i := Length(ds);
  while (i > 1) and (ds[i] = '0') do i := i - 1;
  ds := Copy(ds, 1, i);

  { `p` is where the decimal point sits: the count of digits before it. }
  p := e10 + 1;

  if (p > sig) or (p < -3) then
  begin
    { exponential. FPC writes `1E20` / `1.23E-7` — a sign only when negative,
      and no zero padding of the exponent. }
    if Length(ds) > 1 then s := Copy(ds, 1, 1) + '.' + Copy(ds, 2, Length(ds) - 1)
    else s := ds;
    if p - 1 >= 0 then s := s + 'E' + IntToStr(p - 1)
    else s := s + 'E-' + IntToStr(1 - p);
  end
  else if p <= 0 then
  begin
    { 0.000123456 — the leading zeros are part of the fixed form }
    s := '0.';
    for i := 1 to -p do s := s + '0';
    s := s + ds;
  end
  else if p >= Length(ds) then
  begin
    { the significant digits ran out before the decimal point: pad with zeros
      and emit no fraction at all (100.0 -> `100`, not `100.0`) }
    s := ds;
    for i := Length(ds) + 1 to p do s := s + '0';
  end
  else
    s := Copy(ds, 1, p) + '.' + Copy(ds, p + 1, Length(ds) - p);

  if neg then s := '-' + s;
  Result := s;
end;

function FloatToStr(value: Double): AnsiString;
begin
  Result := FloatToStrSig(value, 15);
end;

{ 10, not 15: a Single carries ~7 decimal digits, and FPC prints 10 of them.
  Measured against FPC 3.2.2 rather than derived — see the interface note. }
function FloatToStr(value: Single): AnsiString;
begin
  Result := FloatToStrSig(value, 10);
end;

function CurrToStr(C: Currency): AnsiString;
begin
  Result := FloatToStr(C);
end;

function StrToCurrDef(const s: AnsiString; def: Currency): Currency;
begin
  Result := StrToFloatDef(s, def);
end;

function StrToCurr(const s: AnsiString): Currency;
begin
  { raises through StrToFloat, and FPC's message for a bad currency is the
    same '"%s" is an invalid float' — verified, not assumed }
  Result := StrToFloat(s);
end;

function FloatToStrF(value: Double; precision: Integer): AnsiString;
var scale: Double; intPart, fracPart: Int64; neg: Boolean; s, fs: AnsiString; i: Integer;
begin
  if precision < 0 then precision := 0;
  if value <> value then begin Result := 'NaN'; Exit; end;
  { same saturation hazard as FloatToStr — see the note there }
  if value > 1.7976931348623157e308 then begin Result := 'Inf'; Exit; end;
  if value < -1.7976931348623157e308 then begin Result := '-Inf'; Exit; end;
  if (value > 9.2e18) or (value < -9.2e18) then
  begin
    Result := FloatToExpStr(value);
    Exit;
  end;
  neg := value < 0.0;
  if neg then value := -value;
  intPart := Trunc(value);
  scale := 1.0;
  for i := 1 to precision do scale := scale * 10.0;
  fracPart := Round(Frac(value) * scale);
  if fracPart >= Trunc(scale) then begin intPart := intPart + 1; fracPart := 0; end;
  s := IntToStr(intPart);
  if precision > 0 then
  begin
    fs := IntToStr(fracPart);
    while Length(fs) < precision do fs := '0' + fs;
    i := Length(fs);
    while (i > 0) and (fs[i] = '0') do i := i - 1;
    if i > 0 then
      s := s + '.' + Copy(fs, 1, i)
    else
      s := s + '.0';
  end;
  if neg then s := '-' + s;
  Result := s;
end;


function StrToFloatDef(const s: AnsiString; def: Double): Double;
begin
  if not ParseFloatCore(s, Result) then Result := def;
end;


function StrToFloat(const s: AnsiString): Double;
begin
  { FPC parity: raises EConvertError on malformed input (used to return 0).
    The integer arms of this family — StrToInt, StrToInt64, StrToQWord — were
    migrated to raising and the FLOAT arms were left behind, so `StrToFloat`
    of user input answered 0 for garbage. That is the silent-wrong-value shape:
    0 is a plausible number the caller carries on with. Message text matches
    FPC's exactly, since callers match on it.
    ([[bug-b-strtofloat-returns-0-for-malformed-input-and-rejects-trailing-space]]) }
  if not TryStrToFloat(s, Result) then
    raise EConvertError.CreateFmt('"%s" is an invalid float', [s]);
end;

function PadLeft(const s: AnsiString; len: Integer; ch: Char): AnsiString;
var n, pad: Integer;
begin
  n := Length(s);
  if n >= len then begin Result := s; Exit; end;
  pad := len - n;
  SetLength(Result, len);
  FillChar(Result[1], pad, Ord(ch));         { pad chars, then the original }
  if n > 0 then Move(s[1], Result[pad + 1], n);
end;

function PadRight(const s: AnsiString; len: Integer; ch: Char): AnsiString;
var n, pad: Integer;
begin
  n := Length(s);
  if n >= len then begin Result := s; Exit; end;
  pad := len - n;
  SetLength(Result, len);
  if n > 0 then Move(s[1], Result[1], n);    { original, then pad chars }
  FillChar(Result[n + 1], pad, Ord(ch));
end;


function Concat(const s1, s2: AnsiString): AnsiString;
begin
  Result := s1 + s2;
end;

function CompareStr(const s1, s2: AnsiString): Integer;
var i, l1, l2, m, c1, c2: Integer;
begin
  l1 := Length(s1); l2 := Length(s2);
  if l1 < l2 then m := l1 else m := l2;
  for i := 1 to m do
  begin
    c1 := Ord(s1[i]); c2 := Ord(s2[i]);
    if c1 <> c2 then begin Result := c1 - c2; Exit; end;
  end;
  Result := l1 - l2;
end;

function CompareText(const s1, s2: AnsiString): Integer;
begin
  Result := CompareStr(LowerCase(s1), LowerCase(s2));
end;

function AnsiCompareStr(const s1, s2: AnsiString): Integer;
begin
  Result := CompareStr(s1, s2);
end;

function AnsiCompareText(const s1, s2: AnsiString): Integer;
begin
  Result := CompareText(s1, s2);
end;

function WideCompareStr(const s1, s2: AnsiString): Integer;
begin
  Result := CompareStr(s1, s2);
end;

function WideCompareText(const s1, s2: AnsiString): Integer;
begin
  Result := CompareText(s1, s2);
end;

function UnicodeCompareStr(const s1, s2: AnsiString): Integer;
begin
  Result := CompareStr(s1, s2);
end;

function UnicodeCompareText(const s1, s2: AnsiString): Integer;
begin
  Result := CompareText(s1, s2);
end;

function SameText(const s1, s2: AnsiString): Boolean;
begin
  Result := CompareText(s1, s2) = 0;
end;

function AnsiSameText(const s1, s2: AnsiString): Boolean;
begin
  Result := SameText(s1, s2);
end;

function SameStr(const s1, s2: AnsiString): Boolean;
begin
  Result := CompareStr(s1, s2) = 0;
end;

function AnsiSameStr(const s1, s2: AnsiString): Boolean;
begin
  Result := SameStr(s1, s2);
end;

function AnsiPos(const substr, s: AnsiString): Integer;
begin
  Result := Pos(substr, s);
end;

function TrimLeft(const s: AnsiString): AnsiString;
var i, n: Integer;
begin
  n := Length(s); i := 1;
  while (i <= n) and (s[i] <= ' ') do Inc(i);
  Result := Copy(s, i, n - i + 1);
end;

function TrimRight(const s: AnsiString): AnsiString;
var i: Integer;
begin
  i := Length(s);
  while (i >= 1) and (s[i] <= ' ') do Dec(i);
  Result := Copy(s, 1, i);
end;

function IsValidIdent(const Ident: AnsiString; AllowDots: Boolean = False;
                      StrictDots: Boolean = False): Boolean;
var i, n: Integer; first: Boolean; c: Char;
begin
  n := Length(Ident);
  Result := n >= 1;
  if not Result then Exit;
  first := True;
  for i := 1 to n do
  begin
    c := Ident[i];
    if first then
    begin
      Result := ((c >= 'A') and (c <= 'Z')) or ((c >= 'a') and (c <= 'z')) or (c = '_');
      first := False;
    end
    else if AllowDots and (c = '.') then
    begin
      { A non-strict dot is simply tolerated and does NOT restart the segment --
        FPC's own loop leaves `first` alone here, so `A..1` is valid without
        StrictDots. Matching the rule rather than the reading of it. }
      if StrictDots then
      begin
        Result := i < n;
        first := True;
      end;
    end
    else
      Result := ((c >= 'A') and (c <= 'Z')) or ((c >= 'a') and (c <= 'z')) or
                (c = '_') or ((c >= '0') and (c <= '9'));
    if not Result then Break;
  end;
end;

{ THE BODIES LIVE HERE AND StrUtils DELEGATES, rather than the reverse or a
  second copy: `strutils` already `uses sysutils`, and a unit that uses StrUtils
  in FPC gets SysUtils' pair anyway. Written as explicit clamps rather than
  leaning on Copy's, because the two functions clamp DIFFERENTLY in FPC --
  LeftStr does not test Count at all and RightStr tests only the upper end --
  and both reach these answers. Asserting the answers keeps them from drifting
  if Copy's edge behaviour is ever tightened.
  feature-pascal-corpus-passrc }
function LeftStr(const S: AnsiString; Count: Integer): AnsiString;
begin
  if Count < 0 then Count := 0;
  if Count > Length(S) then Count := Length(S);
  Result := Copy(S, 1, Count);
end;

function RightStr(const S: AnsiString; Count: Integer): AnsiString;
begin
  if Count < 0 then Count := 0;
  if Count > Length(S) then Count := Length(S);
  Result := Copy(S, Length(S) - Count + 1, Count);
end;

{ Same parser as StrToIntDef, so the two cannot answer differently -- this one
  used to Trim() and so accepted a trailing space that StrToIntDef rejected.
  FPC accepts leading whitespace only. }
function TryStrToInt(const s: AnsiString; var value: Integer): Boolean;
var v: Int64;
begin
  Result := ParseIntPrefixed(s, v);
  if Result then value := Integer(v) else value := 0;   { see TryStrToInt64 }
end;

{ pat matches src at 1-based pos (no allocation, unlike Copy(src,pos,plen)=pat). }
function StrMatchAt(const src, pat: AnsiString; pos, plen, slen: Integer): Boolean;
var j: Integer;
begin
  StrMatchAt := False;
  if pos + plen - 1 > slen then Exit;
  for j := 1 to plen do
    if src[pos + j - 1] <> pat[j] then Exit;
  StrMatchAt := True;
end;

function StringReplace(const S, OldPattern, NewPattern: AnsiString; Flags: TReplaceFlags): AnsiString;
var
  src, pat: AnsiString;
  i, plen, slen, nlen, count, outPos, done: Integer;
  all: Boolean;
begin
  plen := Length(OldPattern);
  if plen = 0 then begin Result := S; Exit; end;
  all := rfReplaceAll in Flags;
  if rfIgnoreCase in Flags then begin src := LowerCase(S); pat := LowerCase(OldPattern); end
  else begin src := S; pat := OldPattern; end;
  slen := Length(S);
  nlen := Length(NewPattern);

  { pass 1: count matches so the result is sized exactly (no O(n^2) append) }
  count := 0; i := 1;
  while i <= slen do
    if StrMatchAt(src, pat, i, plen, slen) then
    begin
      Inc(count); i := i + plen;
      if not all then i := slen + 1;        { only the first match counts }
    end
    else Inc(i);
  if count = 0 then begin Result := S; Exit; end;

  { pass 2: fill — NewPattern at each (replaced) match, else copy the char }
  SetLength(Result, slen + count * (nlen - plen));
  outPos := 1; i := 1; done := 0;
  while i <= slen do
    if (all or (done = 0)) and StrMatchAt(src, pat, i, plen, slen) then
    begin
      if nlen > 0 then Move(NewPattern[1], Result[outPos], nlen);
      outPos := outPos + nlen;
      i := i + plen;
      Inc(done);
    end
    else
    begin
      Result[outPos] := S[i];
      Inc(outPos); Inc(i);
    end;
end;

{ The general form: quote with any character, doubling that character inside.
  QuotedStr is now written as the ' case of THIS rather than carrying its own
  copy of the doubling loop — two spellings of one rule is how they drift
  (devdocs/dev/normalise-dont-special-case.md).
  bug-b-sysutils-string-gaps-found-by-differential }
function AnsiQuotedStr(const s: AnsiString; quote: Char): AnsiString;
var i: Integer; r: AnsiString;
begin
  r := quote;
  for i := 1 to Length(s) do
  begin
    if s[i] = quote then r := r + quote + quote else r := r + s[i];
  end;
  Result := r + quote;
end;

function QuotedStr(const s: AnsiString): AnsiString;
begin
  Result := AnsiQuotedStr(s, '''');
end;

function IsPathSep(c: Char): Boolean;
begin
  Result := (c = '/') or (c = '\');
end;

{ 1-based index of the last path separator, or 0. }
function LastPathSep(const path: AnsiString): Integer;
var i: Integer;
begin
  Result := 0;
  for i := Length(path) downto 1 do
    if IsPathSep(path[i]) then begin Result := i; Exit; end;
end;

function ExtractFileName(const path: AnsiString): AnsiString;
var p: Integer;
begin
  p := LastPathSep(path);
  Result := Copy(path, p + 1, Length(path) - p);
end;

function ExtractFilePath(const path: AnsiString): AnsiString;
var p: Integer;
begin
  p := LastPathSep(path);
  Result := Copy(path, 1, p);
end;

function ExtractFileDir(const path: AnsiString): AnsiString;
var p: Integer;
begin
  p := LastPathSep(path);
  if p <= 1 then Result := Copy(path, 1, p)   { keep a lone leading '/' }
  else Result := Copy(path, 1, p - 1);
end;

{ NOTE `sep + 2`, not `sep + 1`: a dot that is the FIRST character of the
  basename starts a dotfile, it does not introduce an extension. '.hidden' has
  no extension; '.hidden.txt' has '.txt'. Scanning down to sep+1 made the whole
  dotfile name look like one, which is FPC's rule too and matters far more in
  ChangeFileExt below, where it silently ate the name. }
function ExtractFileExt(const path: AnsiString): AnsiString;
var i, sep: Integer;
begin
  Result := '';
  sep := LastPathSep(path);
  for i := Length(path) downto sep + 2 do
    if path[i] = '.' then begin Result := Copy(path, i, Length(path) - i + 1); Exit; end;
end;

{ Same dotfile rule as ExtractFileExt, and here getting it wrong was
  destructive rather than merely wrong: with `sep + 1`, ChangeFileExt('.hidden',
  '.bak') truncated at the leading dot and returned '.bak' — the filename was
  gone. FPC appends, giving '.hidden.bak'. }
function ChangeFileExt(const path, ext: AnsiString): AnsiString;
var i, sep: Integer;
begin
  sep := LastPathSep(path);
  for i := Length(path) downto sep + 2 do
    if path[i] = '.' then begin Result := Copy(path, 1, i - 1) + ext; Exit; end;
  Result := path + ext;
end;

function IncludeTrailingPathDelimiter(const path: AnsiString): AnsiString;
begin
  if (Length(path) > 0) and IsPathSep(path[Length(path)]) then Result := path
  else Result := path + '/';
end;

function ExcludeTrailingPathDelimiter(const path: AnsiString): AnsiString;
begin
  if (Length(path) > 1) and IsPathSep(path[Length(path)]) then
    Result := Copy(path, 1, Length(path) - 1)
  else
    Result := path;
end;

function SetDirSeparators(const path: AnsiString): AnsiString;
var i: Integer;
begin
  Result := path;
  for i := 1 to Length(Result) do
    if IsPathSep(Result[i]) then Result[i] := '/';
end;

function FmtPCharStr(p: Pointer): AnsiString;
var pc: PChar; i: Integer; r: AnsiString;
begin
  r := '';
  if p <> nil then
  begin
    pc := PChar(p); i := 0;
    while pc[i] <> #0 do begin r := r + pc[i]; Inc(i); end;
  end;
  Result := r;
end;

{ Read one array-of-const element as Int64 / string / double. }
function FmtArgInt(const v: TVarRec): Int64;
begin
  case v.VType of
    vtInteger: Result := v.VInteger;
    vtInt64:   Result := PInt64Rec(v.VInt64)^;
    vtQWord:   Result := Int64(PQWordRec(v.VInt64)^);   { Int64, and that is the
                 CONTRACT rather than a limitation: `%d` is the signed
                 conversion and `%u` is the unsigned one. Measured 2026-09-06
                 against fpc 3.2.2 with q = 18000000000000000000 --
                 Format('%d') gives -446744073709551616 in BOTH compilers and
                 Format('%u') gives the full value in both. Do not "fix" this
                 arm to be unsigned; it would diverge from the oracle. }
    vtBoolean: Result := Ord(v.VBoolean);
    vtChar:    Result := Ord(v.VChar);
    vtExtended: Result := Trunc(PDoubleRec(v.VExtended)^);
  else
    Result := 0;
  end;
end;

function FmtArgStr(const v: TVarRec): AnsiString;
begin
  case v.VType of
    vtAnsiString: Result := FmtPCharStr(v.VAnsiString);
    vtPChar:      Result := FmtPCharStr(v.VPChar);
    vtChar:       Result := v.VChar;
    vtInteger:    Result := IntToStr(v.VInteger);
    vtInt64:      Result := IntToStr(PInt64Rec(v.VInt64)^);
    vtQWord:      Result := UIntToStr(PQWordRec(v.VInt64)^);
    vtBoolean:    if v.VBoolean then Result := 'TRUE' else Result := 'FALSE';
    vtExtended:   Result := FloatToStr(PDoubleRec(v.VExtended)^);
  else
    Result := '';
  end;
end;

function FmtArgFloat(const v: TVarRec): Double;
begin
  case v.VType of
    vtExtended: Result := PDoubleRec(v.VExtended)^;
    vtInteger:  Result := v.VInteger;
    vtInt64:    Result := PInt64Rec(v.VInt64)^;
    vtQWord:    Result := PQWordRec(v.VInt64)^;
  else
    Result := 0;
  end;
end;

{ Keep the first `keep` digits of an EXACT digit string, rounding
  half-AWAY-FROM-ZERO on the remainder — FPC's fixed-point rule, and the one
  the old scaled-Int64 FmtFixed implemented with `+ 0.5` ('%.2f' of 0.125 is
  '0.13' here, where glibc's half-to-even gives '0.12'). Deliberately NOT
  ExDecRound: that one is half-to-EVEN because it serves %g/%e, where the rule
  is glibc's.

  `keep` may be 0 — "everything is below the last printed place", which still
  has to round (0.5 at %.0f is '1'). A carry out of the leading digit sets
  carryOut and the caller prepends the '1'. Placed here, below the
  CHANGE-ONE-CHANGE-BOTH block, because pylib.pas has no Format and so needs
  no copy of it. }
function ExDecKeepHalfUp(const s: AnsiString; keep: Integer;
                         var carryOut: Boolean): AnsiString;
var r: AnsiString; i, c: Integer;
begin
  carryOut := False;
  if keep >= Length(s) then
  begin
    r := s;
    for i := Length(s) + 1 to keep do r := r + '0';
    Result := r;
    Exit;
  end;
  r := Copy(s, 1, keep);
  if s[keep + 1] >= '5' then
  begin
    i := keep;
    while i >= 1 do
    begin
      c := Ord(r[i]) - Ord('0') + 1;
      if c < 10 then begin r[i] := Chr(Ord('0') + c); break; end;
      r[i] := '0';
      i := i - 1;
    end;
    if i = 0 then carryOut := True;
  end;
  Result := r;
end;

{ Fixed-point: exactly prec fraction digits, rounded (printf %f).

  Runs on the EXACT decimal expansion of the double. The old body scaled the
  whole value into an Int64 (`Trunc(v * 10^prec + 0.5)`), which had two
  thresholds: past 2^53 the scaled double could not hold the value exactly and
  the last digits were silently wrong (from |v| ~ 9e13 at prec = 2 — cents,
  byte counts, nanosecond timestamps), and past 2^63 the Trunc wrapped to
  Int64.Min and every value printed the same string, with a minus sign INSIDE
  the fraction: '-92233720368547758.-8'. A large `prec` overflowed `k` the same
  way ('%.20f' of 0.1). Exact integer expansion has neither threshold —
  bug-b-format-fixed-overflows-int64-and-loses-digits.

  Past 2^53 we now print the double's TRUE digits, where FPC prints an
  18-significant-digit approximation and, past ~1e300, abandons the fixed form
  for '1.0E+0300'. That divergence is deliberate and is the display-policy
  question in decide-float-fixed-output-exact-or-fpc-17-digit-cap; printing
  digits that are not the value's digits is not an option on either answer. }
function FmtFixed(v: Double; prec: Integer): AnsiString;
var neg, carry, allZero: Boolean;
    ds, digits, frac: AnsiString;
    e10, q, keep, i: Integer;
begin
  if prec < 0 then prec := 0;
  if v <> v then begin Result := 'Nan'; Exit; end;
  if v > 1.7976931348623157e308 then begin Result := '+Inf'; Exit; end;
  if v < -1.7976931348623157e308 then begin Result := '-Inf'; Exit; end;
  neg := v < 0;
  if neg then v := -v;
  if v = 0.0 then
  begin
    { ExDecDigits would answer '0' with decExp -1074 and send us padding a
      thousand leading zeros for nothing }
    ds := '0'; e10 := 0;
  end
  else
    ExDecDigits(v, ds, e10);   { v = ds[1].ds[2..] * 10^e10, no leading zero }
  q := e10 + 1;                { digits before the point }
  if q < 0 then
  begin
    for i := 1 to -q do ds := '0' + ds;
    q := 0;
  end;
  keep := q + prec;
  digits := ExDecKeepHalfUp(ds, keep, carry);
  if carry then begin digits := '1' + digits; q := q + 1; end;
  Result := Copy(digits, 1, q);
  if Result = '' then Result := '0';
  if prec > 0 then
  begin
    frac := Copy(digits, q + 1, prec);
    Result := Result + '.' + frac;
  end;
  { FPC drops the sign once every digit has rounded away: '%.0f' of -0.4 is
    '0', not glibc's '-0'. }
  allZero := True;
  for i := 1 to Length(digits) do
    if digits[i] <> '0' then begin allZero := False; break; end;
  if neg and not allZero then Result := '-' + Result;
end;

{ ---- %g and %e ------------------------------------------------------------
  FPC's `%g` is ffGeneral and its `%e` is ffExponent, and both honour an
  explicit precision. Ours ignored `%.3g` entirely and had no `%e` branch at
  all — an unknown specifier is emitted literally AND does not advance the
  argument index, so a single `%e` shifted every argument after it.

  What these do NOT reproduce is FPC's DIGIT COUNT with no precision given:
  FPC's `%g` prints 17 significant digits and its `%e` 16 decimals, which needs
  an exact big-integer conversion (a real dtoa) rather than scaling a double.
  We render what we can render correctly — 15 significant digits, the same rule
  FloatToStr uses — and the divergence is recorded in
  compat-pascal-format-g-and-e-specifiers rather than faked. The
  explicitly-requested-precision paths, which are a contract, are exact. }

{ `sig` significant digits, in the general form: fixed when the decimal point
  lands inside [-3, sig], exponential otherwise, exactly as FloatToStr. }
function FmtGeneral(v: Double; sig: Integer): AnsiString;
begin
  { FPC's precision for %g and %e counts SIGNIFICANT DIGITS, not decimals, and
    clamps at a minimum of two — `%.1g` of 1/3 is `0.33`, not `0.3`. Measured
    against an FPC build; the rule is the same for both specifiers. }
  if sig < 2 then sig := 2;
  { 17, not 15. FloatToStrSig hands anything past 15 to the exact expansion,
    so the digits above 15 are correctly rounded rather than scaled -- the
    thing compat-pascal-format-g-and-e-specifiers was waiting for. }
  if sig > 17 then sig := 17;
  FmtGeneral := FloatToStrSig(v, sig);
end;

{ FPC's exponential SPELLING, which is a THIRD one, distinct from FloatToStr's
  `1E20` and FloatToExpStr's `1E+20`: a mantissa, then `E`, then a sign that is
  always present, then at least three exponent digits —
  `3.3333333333333331E-001`. Measured against an FPC build, not assumed. }
function FmtExponentEx(v: Double; sig, expDigits: Integer): AnsiString;
var neg: Boolean; e10: Integer; ds, mant, es: AnsiString;
begin
  { `sig` is significant digits (FPC's rule, min 2); 17 is the most a Double
    can carry, and the default. `expDigits` is the MINIMUM width of the
    exponent field: 3 for Format's '%e' (FPC prints E+000), but FloatToStrF's
    ffExponent takes it from its Digits argument, which is why this is a
    parameter rather than the constant it used to be. }
  if expDigits < 1 then expDigits := 1;
  if sig < 2 then sig := 2;
  if sig > 17 then sig := 17;
  if v <> v then begin FmtExponentEx := 'NaN'; Exit; end;
  { Infinity BEFORE anything else: the old normalise loop divided by ten until
    the value dropped below ten, and Inf/10.0 is Inf, so it never terminated. }
  if v > 1.7976931348623157e308 then begin FmtExponentEx := 'Inf'; Exit; end;
  if v < -1.7976931348623157e308 then begin FmtExponentEx := '-Inf'; Exit; end;
  neg := v < 0.0;
  if neg then v := -v;
  if v = 0.0 then
  begin
    ds := '0'; e10 := 0;
  end
  else
  begin
    { The EXACT expansion, not a double scaled by powers of ten. The old code
      normalised with `while m >= 10.0 do m := m / 10.0`, which is one rounding
      per step -- a hundred of them for 1e100, and the error reached the 16th
      digit: 1e100 printed as 1.0000000000000007E+100 where both FPC and
      CPython give 1.0000000000000000E+100, and 1e200 came out with the wrong
      EXPONENT (E+200 for a value just under it). ExDecDigits/ExDecRound do the
      conversion in exact integer arithmetic and round half-to-even on a
      genuine remainder. }
    ExDecDigits(v, ds, e10);
    ExDecRound(ds, e10, sig);
  end;
  { the exponent form is fixed-width, so a short expansion pads out }
  while Length(ds) < sig do ds := ds + '0';
  mant := Copy(ds, 1, 1);
  if sig > 1 then mant := mant + '.' + Copy(ds, 2, sig - 1);
  if neg then mant := '-' + mant;
  es := IntToStr(Abs(e10));
  while Length(es) < expDigits do es := '0' + es;
  if e10 < 0 then es := '-' + es else es := '+' + es;
  FmtExponentEx := mant + 'E' + es;
end;

function FmtExponent(v: Double; sig: Integer): AnsiString;
begin
  { Format's '%e' width — FPC prints 3.14159E+000. One implementation, one
    place the rounding lives. }
  FmtExponent := FmtExponentEx(v, sig, 3);
end;

{ Width padding is ALWAYS spaces. Zero-padding is what the precision does, and
  only for the integer types — see FmtIntPrec. }
function FmtPad(const s: AnsiString; width: Integer; leftAlign: Boolean): AnsiString;
var pad: AnsiString; need, k: Integer;
begin
  need := width - Length(s);
  if need <= 0 then begin Result := s; Exit; end;
  pad := '';
  for k := 1 to need do pad := pad + ' ';
  if leftAlign then Result := s + pad else Result := pad + s;
end;

{ Apply an integer precision: a MINIMUM number of digits, zero-filled on the
  left, with the sign staying outside the zeros ('%.5d' of -42 is '-00042', not
  '000-42'). A value already that long is never truncated — precision is a
  floor for integers, unlike '%s' where it is a ceiling. }
function FmtIntPrec(const s: AnsiString; hasPrec: Boolean; prec: Integer): AnsiString;
var body, sign: AnsiString; k: Integer;
begin
  if not hasPrec then begin Result := s; Exit; end;
  sign := ''; body := s;
  if (Length(body) > 0) and ((body[1] = '-') or (body[1] = '+')) then
  begin sign := body[1]; body := Copy(body, 2, Length(body) - 1); end;
  for k := Length(body) + 1 to prec do body := '0' + body;
  Result := sign + body;
end;

{ Was the argument a 32-bit integer rather than an Int64? It decides how wide a
  negative value prints in hex: '%x' of Integer(-1) is FFFFFFFF, of Int64(-1)
  sixteen nibbles. FmtArgInt widens everything to Int64, so the original width
  is only recoverable from the variant tag. }
function FmtArgIs32(const v: TVarRec): Boolean;
begin
  Result := (v.VType = vtInteger) or (v.VType = vtBoolean) or (v.VType = vtChar);
end;

{ Insert ThousandSeparator every three digits of the INTEGER part of an already
  formatted fixed-point string. Grouping starts from the decimal point, so it
  has to find that point first — grouping from the right end of the whole
  string would put a separator inside the fraction ('1,234.50' vs '1,234.5,0').
  A leading sign is kept out of the count for the same reason. }
function FmtGroup(const s: AnsiString): AnsiString;
var sign, ip, rest, g: AnsiString; k, dot, cnt: Integer;
begin
  sign := ''; ip := s;
  if (Length(ip) > 0) and ((ip[1] = '-') or (ip[1] = '+')) then
  begin sign := ip[1]; ip := Copy(ip, 2, Length(ip) - 1); end;
  dot := 0;
  for k := 1 to Length(ip) do
    if ip[k] = DecimalSeparator then begin dot := k; Break; end;
  if dot = 0 then begin rest := ''; end
  else begin rest := Copy(ip, dot, Length(ip) - dot + 1); ip := Copy(ip, 1, dot - 1); end;
  g := ''; cnt := 0;
  for k := Length(ip) downto 1 do
  begin
    g := ip[k] + g;
    Inc(cnt);
    if (cnt mod 3 = 0) and (k > 1) then g := ThousandSeparator + g;
  end;
  Result := sign + g + rest;
end;

{ '%m': the value grouped to CurrencyDecimals places, then wrapped by the
  CurrencyFormat / NegCurrFormat layout codes. Only the layouts FPC's defaults
  select (1 and 5) plus their obvious siblings are laid out; anything else
  falls back to value-then-symbol rather than dropping the symbol. }
function FmtCurrency(v: Double; prec: Integer): AnsiString;
var body: AnsiString; neg: Boolean;
begin
  neg := v < 0;
  if neg then v := -v;
  body := FmtGroup(FmtFixed(v, prec));
  if neg then
    case NegCurrFormat of
      0: Result := '(' + CurrencyString + body + ')';
      1: Result := '-' + CurrencyString + body;
      2: Result := CurrencyString + '-' + body;
      3: Result := CurrencyString + body + '-';
      4: Result := '(' + body + CurrencyString + ')';
      6: Result := body + '-' + CurrencyString;
      7: Result := body + CurrencyString + '-';
      8: Result := '-' + body + ' ' + CurrencyString;
      9: Result := '-' + CurrencyString + ' ' + body;
      10: Result := CurrencyString + ' ' + body + '-';
    else
      Result := '-' + body + CurrencyString;    { 5, and the default }
    end
  else
    case CurrencyFormat of
      0: Result := CurrencyString + body;
      2: Result := CurrencyString + ' ' + body;
      3: Result := body + ' ' + CurrencyString;
    else
      Result := body + CurrencyString;          { 1, and the default }
    end;
end;

function FloatToStrF(value: Double; format: TFloatFormat;
                     Precision, Digits: Integer): AnsiString;
begin
  { FPC defines its own Format's float conversions IN TERMS of FloatToStrF, so
    routing this onto the same five helpers Format already uses is the shared
    path, not a parallel one: '%f' is ffFixed, '%g' ffGeneral, '%e' ffExponent,
    '%n' ffNumber, '%m' ffCurrency, and the rounding lives in one place. }
  case format of
    ffFixed:    Result := FmtFixed(value, Digits);
    ffNumber:   Result := FmtGroup(FmtFixed(value, Digits));
    ffCurrency: Result := FmtCurrency(value, Digits);
    { the ONE format that reads Digits as an exponent width rather than as a
      decimal count — see the interface table }
    ffExponent: Result := FmtExponentEx(value, Precision, Digits);
  else
    Result := FmtGeneral(value, Precision);   { ffGeneral }
  end;
end;

function Format(const fmt: AnsiString; const args: array of const): AnsiString;
var
  i, j, n, argIdx, idxVal, width, prec: Integer;
  c: Char;
  leftAlign, hasPrec: Boolean;
  piece, r: AnsiString;
  iv: Int64;
begin
  r := ''; i := 1; n := Length(fmt); argIdx := 0;
  while i <= n do
  begin
    c := fmt[i];
    if c <> '%' then begin r := r + c; Inc(i); Continue; end;
    Inc(i);                                        { past '%' }
    if (i <= n) and (fmt[i] = '%') then begin r := r + '%'; Inc(i); Continue; end;

    { Delphi's spec is  %[index:][-][width][.prec]type  and is NOT printf's.
      There is no '0' flag: the leading zero of '%05d' is simply part of the
      WIDTH, so it pads with spaces to 5 — zero-filling is the precision's job
      ('%.5d'). Parsing it as a flag is the classic way to get '00042' where FPC
      and Delphi both give '   42'. }

    { optional argument index — digits followed by ':'. Only committed to once
      the ':' is seen, because those same digits are otherwise the width. }
    j := i; idxVal := 0;
    while (j <= n) and (fmt[j] >= '0') and (fmt[j] <= '9') do
    begin idxVal := idxVal * 10 + (Ord(fmt[j]) - Ord('0')); Inc(j); end;
    if (j > i) and (j <= n) and (fmt[j] = ':') then
    begin
      { it moves the cursor: the specifiers AFTER an indexed one continue from
        there rather than resuming where they left off }
      argIdx := idxVal;
      i := j + 1;
    end;

    leftAlign := False;
    while (i <= n) and (fmt[i] = '-') do begin leftAlign := True; Inc(i); end;
    width := 0;
    { '*' takes the width from the argument list, consumed BEFORE the value it
      applies to. FPC ignores the sign of a '*' width — '%*d' with -6 pads to
      six on the right, it does not left-align — so take the magnitude. }
    if (i <= n) and (fmt[i] = '*') then
    begin
      if argIdx < Length(args) then width := Integer(FmtArgInt(args[argIdx]));
      if width < 0 then width := -width;
      Inc(argIdx); Inc(i);
    end
    else
      while (i <= n) and (fmt[i] >= '0') and (fmt[i] <= '9') do
      begin width := width * 10 + (Ord(fmt[i]) - Ord('0')); Inc(i); end;
    hasPrec := False; prec := 0;
    if (i <= n) and (fmt[i] = '.') then
    begin
      Inc(i); hasPrec := True;
      if (i <= n) and (fmt[i] = '*') then
      begin
        if argIdx < Length(args) then prec := Integer(FmtArgInt(args[argIdx]));
        if prec < 0 then prec := 0;
        Inc(argIdx); Inc(i);
      end
      else
        while (i <= n) and (fmt[i] >= '0') and (fmt[i] <= '9') do
        begin prec := prec * 10 + (Ord(fmt[i]) - Ord('0')); Inc(i); end;
    end;
    if i > n then Break;
    c := fmt[i]; Inc(i);

    piece := '';
    case c of
      'd':
        begin
          if argIdx < Length(args) then
            piece := FmtIntPrec(IntToStr(FmtArgInt(args[argIdx])), hasPrec, prec);
          Inc(argIdx);
        end;
      'u':
        begin
          { NOT a synonym for 'd': it shared that arm, so '%u' of any negative
            bit pattern printed the signed value. Width is recovered from the
            variant tag exactly as '%x' below does it -- FmtArgInt sign-extends
            a 32-bit argument on the way in, and '%u' of Integer(-1) is
            4294967295, not the 64-bit two's complement.
            ([[bug-b-format-percent-u-prints-a-signed-value]]) }
          if argIdx < Length(args) then
          begin
            iv := FmtArgInt(args[argIdx]);
            if FmtArgIs32(args[argIdx]) then iv := Int64(LongWord(iv));
            piece := FmtIntPrec(UIntToStr(QWord(iv)), hasPrec, prec);
          end;
          Inc(argIdx);
        end;
      'x', 'X':
        begin
          if argIdx < Length(args) then
          begin
            iv := FmtArgInt(args[argIdx]);
            { a 32-bit argument prints 32-bit: FmtArgInt sign-extended it on the
              way in, and without narrowing it back every negative Integer would
              come out as sixteen nibbles }
            if FmtArgIs32(args[argIdx]) then iv := Int64(LongWord(iv));
            piece := FmtIntPrec(IntToHex(iv, 0), hasPrec, prec);
          end;
          Inc(argIdx);
        end;
      's':
        begin
          if argIdx < Length(args) then piece := FmtArgStr(args[argIdx]);
          if hasPrec and (Length(piece) > prec) then piece := Copy(piece, 1, prec);
          Inc(argIdx);
        end;
      'f':
        begin
          if argIdx < Length(args) then
          begin
            if hasPrec then piece := FmtFixed(FmtArgFloat(args[argIdx]), prec)
            else piece := FmtFixed(FmtArgFloat(args[argIdx]), 2);
          end;
          Inc(argIdx);
        end;
      'g':
        begin
          if argIdx < Length(args) then
          begin
            { no precision given -> FPC prints 17 significant digits
              ('%g' of 1/3 is 0.33333333333333331), not FloatToStr's 15 }
            if hasPrec then piece := FmtGeneral(FmtArgFloat(args[argIdx]), prec)
            else piece := FmtGeneral(FmtArgFloat(args[argIdx]), 17);
          end;
          Inc(argIdx);
        end;
      'e':
        begin
          if argIdx < Length(args) then
          begin
            { 17 significant digits, not 15: FPC's default '%e' is
              3.1415900000000000E+000 -- one digit before the point and 16
              after. FmtExponent's argument is a count of SIGNIFICANT digits
              (which is why '%.4e' of 3.14159 is 3.142, four in total), so the
              default has to be 17, the number that round-trips a Double. }
            if hasPrec then piece := FmtExponent(FmtArgFloat(args[argIdx]), prec)
            else piece := FmtExponent(FmtArgFloat(args[argIdx]), 17);
          end;
          Inc(argIdx);
        end;
      'n':
        begin
          { fixed-point with ThousandSeparator grouping; two decimals unless a
            precision says otherwise }
          if argIdx < Length(args) then
          begin
            if hasPrec then piece := FmtGroup(FmtFixed(FmtArgFloat(args[argIdx]), prec))
            else piece := FmtGroup(FmtFixed(FmtArgFloat(args[argIdx]), 2));
          end;
          Inc(argIdx);
        end;
      'm':
        begin
          if argIdx < Length(args) then
          begin
            if hasPrec then piece := FmtCurrency(FmtArgFloat(args[argIdx]), prec)
            else piece := FmtCurrency(FmtArgFloat(args[argIdx]), CurrencyDecimals);
          end;
          Inc(argIdx);
        end;
      { PXX EXTENSION, deliberately not FPC-parity: '%c' is not in the Delphi
        spec, and FPC's handling of it is unspecified garbage (it re-emits the
        previous conversion — '%x|%c' of [255,'q'] prints 'FF|FF'). Printing
        the character, as C's printf does, is the useful reading. }
      'c':
        begin
          if argIdx < Length(args) then piece := Chr(Integer(FmtArgInt(args[argIdx])));
          Inc(argIdx);
        end;
    else
      piece := '%' + c;                            { unknown spec — emit literally }
    end;
    r := r + FmtPad(piece, width, leftAlign);
  end;
  Result := r;
end;

function UnicodeFormat(const fmt: AnsiString; const args: array of const): AnsiString;
begin
  Result := Format(fmt, args);
end;

function BoolToStr(B: Boolean; UseBoolStrs: Boolean): AnsiString;
begin
  if UseBoolStrs then
  begin
    if B then Result := 'True' else Result := 'False';
  end
  else
  begin
    if B then Result := '-1' else Result := '0';
  end;
end;

function BoolToStr(B: Boolean; const TrueS, FalseS: AnsiString): AnsiString;
begin
  if B then Result := TrueS else Result := FalseS;
end;

function DirentByte(buf: Pointer; off: Integer): Byte;
begin
  Result := PByte(Pointer(Int64(buf) + off))^;
end;

function DirentWordLE(buf: Pointer; off: Integer): Integer;
begin
  Result := Integer(DirentByte(buf, off)) + Integer(DirentByte(buf, off + 1)) * 256;
end;

function DirentName(buf: Pointer; off: Integer): AnsiString;
var s: AnsiString; b: Byte;
begin
  s := '';
  b := DirentByte(buf, off);
  while b <> 0 do
  begin
    s := s + Chr(b);
    off := off + 1;
    b := DirentByte(buf, off);
  end;
  Result := s;
end;

function GetDirectoryContents(const path: AnsiString; var list: TFileInfoArray): Boolean;
var
  fd: Integer;
  buf: array[0..4095] of Byte;
  n: Int64;
  off, reclen, idx: Integer;
  name: AnsiString;
  dtype: Byte;
  stat: TPalFileStat;
begin
  SetLength(list, 0);
  fd := PalOpen(PChar(path), PAL_OPEN_READ or PAL_OPEN_DIRECTORY, 0);
  if fd < 0 then
  begin
    Result := False;
    Exit;
  end;

  Result := True;
  n := PalGetDents64(fd, @buf[0], 4096);
  while n > 0 do
  begin
    off := 0;
    while off < Integer(n) do
    begin
      reclen := DirentWordLE(@buf[0], off + 16);
      if reclen <= 0 then
      begin
        Result := False;
        off := Integer(n);
      end
      else
      begin
        dtype := DirentByte(@buf[0], off + 18);
        name := DirentName(@buf[0], off + 19);
        if (name <> '.') and (name <> '..') then
        begin
          idx := Length(list);
          SetLength(list, idx + 1);
          list[idx].Name := name;
          list[idx].IsDir := dtype = PAL_DIRENT_DIR;
          list[idx].Size := -1;
          list[idx].ModifiedTime := 0;
          if PalStatAt(fd, PChar(name), stat) >= 0 then
          begin
            list[idx].IsDir := stat.IsDir;
            list[idx].Size := stat.Size;
            list[idx].ModifiedTime := stat.MTimeSec;
          end;
        end;
        off := off + reclen;
      end;
    end;
    n := PalGetDents64(fd, @buf[0], 4096);
  end;

  if n < 0 then Result := False;
  fd := PalClose(fd);
end;

{ ---- FindFirst / FindNext / FindClose ------------------------------------

  Streams the directory with PalGetDents64 rather than snapshotting it into an
  array. GetDirectoryContents just above does snapshot, and reusing it was the
  obvious move -- it is rejected on a SEMANTIC ground, not a performance one:
  it drops `.` and `..`, and FindFirst must return them. Building on a filter
  this surface is required not to have would have been correct on every test a
  casual fixture writes and wrong for fpc's own cfileutl.pas. }

const
  { POSIX st_mode bits. Spelled here because this unit has no <sys/stat.h> to
    include and platform_types carries the raw Mode without interpreting it. }
  SU_S_IFMT   = $F000;
  SU_S_IFDIR  = $4000;
  SU_S_IFCHR  = $2000;
  SU_S_IFBLK  = $6000;
  SU_S_IFIFO  = $1000;
  SU_S_IFLNK  = $A000;
  SU_S_IFSOCK = $C000;
  SU_S_IWUSR  = $0080;

type
  TFindState = record
    fd: Integer;
    dirPrefix: AnsiString;
    mask: AnsiString;
    searchAttr: LongInt;
    buf: array[0..4095] of Byte;
    bufLen: Integer;
    bufOff: Integer;
    exhausted: Boolean;
    oneShot: Boolean;   { a wildcard-free path: exactly one candidate }
  end;
  PFindState = ^TFindState;

{ fpc's FNMatch (rtl/unix/sysutils.pp:809), reduced to what it actually
  supports: `*` and `?`, no character classes. Recursive on `*` for the same
  reason FPC is -- a greedy scan cannot backtrack, and `*a*b` needs to.

  `?` matches a byte, not a codepoint. FPC's does UTF-8 codepoint stepping when
  the name's codepage says UTF-8; this unit has no per-string codepage, so the
  byte reading is the honest one rather than a silently different one. }
function FNMatch(const pattern, name: AnsiString): Boolean;

  function DoMatch(i, j: Integer): Boolean;
  var found: Boolean;
  begin
    found := True;
    while found and (i <= Length(pattern)) do
    begin
      if pattern[i] = '?' then
      begin
        found := j <= Length(name);
        Inc(j);
        Inc(i);
      end
      else if pattern[i] = '*' then
      begin
        { Collapse a run of '*' and account for any '?' inside it. }
        while (i <= Length(pattern)) and (pattern[i] = '*') do Inc(i);
        if i > Length(pattern) then
        begin
          { Trailing '*' eats the rest, whatever is left. }
          DoMatch := True;
          Exit;
        end;
        { Try every remaining position. j..Length+1 rather than j..Length, so
          a pattern whose tail can match EMPTY still gets its chance. }
        while j <= Length(name) + 1 do
        begin
          if DoMatch(i, j) then
          begin
            DoMatch := True;
            Exit;
          end;
          Inc(j);
        end;
        DoMatch := False;
        Exit;
      end
      else
      begin
        found := (j <= Length(name)) and (pattern[i] = name[j]);
        Inc(i);
        Inc(j);
      end;
    end;
    DoMatch := found and (j = Length(name) + 1);
  end;

begin
  FNMatch := DoMatch(1, 1);
end;

{ fpc's LinuxToWinAttr (rtl/unix/sysutils.pp:688), which is where the DOS
  attribute word for a unix entry comes from. Every entry carries faArchive --
  that is FPC's, and it is why faArchive is forced into the search filter. }
function UnixModeToAttr(const baseName: AnsiString; mode: Integer; isLink, linkIsDir: Boolean): LongInt;
var a: LongInt; fmt: Integer;
begin
  a := faArchive;
  fmt := mode and SU_S_IFMT;
  if fmt = SU_S_IFDIR then a := a or faDirectory;
  { A leading dot hides it -- but `.` and `..` are NOT hidden, which is what the
    second-character test is for and why it is not just `[1] = '.'`. }
  if (Length(baseName) >= 2) and (baseName[1] = '.') and (baseName[2] <> '.') then
    a := a or faHidden;
  if (mode and SU_S_IWUSR) = 0 then a := a or faReadOnly;
  if (fmt = SU_S_IFSOCK) or (fmt = SU_S_IFBLK) or (fmt = SU_S_IFCHR) or (fmt = SU_S_IFIFO) then
    a := a or faSysFile;
  if isLink then
  begin
    a := a or faSymLink;
    { FPC reports a link to a directory AS a directory, matching Windows. }
    if linkIsDir then a := a or faDirectory;
  end;
  UnixModeToAttr := a;
end;

{ Stat one candidate and, if the filter accepts it, fill the record. Returns
  False when the entry vanished between readdir and stat (a race that is
  ordinary, not an error) or when the filter rejects it. }
function FindFillOne(st: PFindState; const fullPath, baseName: AnsiString;
                     var Rslt: TRawByteSearchRec): Boolean;
var info, linkInfo: TPalFileStat; attr: LongInt; isLink, linkIsDir: Boolean;
begin
  FindFillOne := False;
  isLink := False;
  linkIsDir := False;
  { Follow links unless the caller asked for faSymLink, which is FPC's rule:
    without it a link reports its TARGET and never carries faSymLink at all. }
  if (st^.searchAttr and faSymLink) <> 0 then
  begin
    if PalLstat(PChar(fullPath), info) <> 0 then Exit;
    isLink := (info.Mode and SU_S_IFMT) = SU_S_IFLNK;
    if isLink then
      linkIsDir := (PalStat(PChar(fullPath), linkInfo) = 0) and linkInfo.IsDir;
  end
  else
    if PalStat(PChar(fullPath), info) <> 0 then Exit;

  attr := UnixModeToAttr(baseName, info.Mode, isLink, linkIsDir);
  { THE FILTER, and its polarity is the whole subtlety: an entry is accepted
    when every bit it HAS is also in searchAttr -- not when it has any bit the
    caller asked for. So faDirectory alone accepts a plain directory and
    rejects a hidden one, because faHidden is a bit the entry has and the
    caller did not ask for. }
  if (attr and not st^.searchAttr) <> 0 then Exit;

  Rslt.Name := baseName;
  Rslt.Attr := attr;
  Rslt.Size := info.Size;
  Rslt.Time := info.MTimeSec;
  Rslt.Mode := info.Mode;
  FindFillOne := True;
end;

{ Pull the next raw name out of the dirent stream, refilling the buffer as
  needed. Returns '' at end of directory. }
function FindNextRawName(st: PFindState): AnsiString;
var reclen: Integer; n: Int64;
begin
  FindNextRawName := '';
  if st^.exhausted then Exit;
  while True do
  begin
    if st^.bufOff >= st^.bufLen then
    begin
      n := PalGetDents64(st^.fd, @st^.buf[0], 4096);
      if n <= 0 then
      begin
        st^.exhausted := True;
        Exit;
      end;
      st^.bufLen := Integer(n);
      st^.bufOff := 0;
    end;
    reclen := DirentWordLE(@st^.buf[0], st^.bufOff + 16);
    { A zero or negative reclen would loop forever on a corrupt buffer. Treat
      it as end-of-directory rather than spinning. }
    if reclen <= 0 then
    begin
      st^.exhausted := True;
      Exit;
    end;
    FindNextRawName := DirentName(@st^.buf[0], st^.bufOff + 19);
    st^.bufOff := st^.bufOff + reclen;
    if FindNextRawName <> '' then Exit;
  end;
end;

procedure FindClose(var Rslt: TRawByteSearchRec);
var st: PFindState;
begin
  st := PFindState(Rslt.FindHandle);
  if st = nil then Exit;
  if st^.fd >= 0 then st^.fd := PalClose(st^.fd);
  { Drop the managed fields before the record's storage goes away. }
  st^.dirPrefix := '';
  st^.mask := '';
  Dispose(st);
  Rslt.FindHandle := nil;
end;

function FindNext(var Rslt: TRawByteSearchRec): LongInt;
var st: PFindState; nm: AnsiString;
begin
  FindNext := -1;
  st := PFindState(Rslt.FindHandle);
  if st = nil then Exit;
  { A wildcard-free path is a single candidate, already answered by FindFirst. }
  if st^.oneShot then
  begin
    st^.exhausted := True;
    Exit;
  end;
  if st^.fd < 0 then Exit;
  while True do
  begin
    nm := FindNextRawName(st);
    if nm = '' then Exit;
    if FNMatch(st^.mask, nm) then
      if FindFillOne(st, st^.dirPrefix + nm, nm, Rslt) then
      begin
        FindNext := 0;
        Exit;
      end;
  end;
end;

function FindFirst(const Path: AnsiString; Attr: LongInt; out Rslt: TRawByteSearchRec): LongInt;
var st: PFindState; i, cut: Integer; openDir: AnsiString;
begin
  Rslt.Time := 0;
  Rslt.Size := 0;
  Rslt.Attr := 0;
  Rslt.Name := '';
  Rslt.ExcludeAttr := 0;
  Rslt.FindHandle := nil;
  Rslt.Mode := 0;
  FindFirst := -1;
  if Path = '' then Exit;

  New(st);
  st^.fd := -1;
  st^.dirPrefix := '';
  st^.mask := '';
  st^.bufLen := 0;
  st^.bufOff := 0;
  st^.exhausted := False;
  st^.oneShot := False;
  { faArchive and faReadOnly go in unconditionally -- fpc's own comment says
    "We always also search for readonly and archive, regardless of Attr", and
    without it every call returns nothing, because every unix entry carries
    faArchive. }
  st^.searchAttr := Attr or faArchive or faReadOnly;
  Rslt.FindHandle := st;
  { ExcludeAttr stays 0. FPC's modern path zeroes the record and never writes
    it -- the field is a leftover from the Dos-unit surface -- so computing a
    plausible `not Attr` here would be this RTL inventing a value the oracle
    does not produce, on a field callers can read. }

  { No metacharacter means the path names ONE file, and FPC does not open a
    directory at all in that case. Keeping that matters: `FindFirst(exactName)`
    is how callers test existence-with-attributes, and a directory scan would
    give a different answer for a path whose parent is unreadable. }
  cut := 0;
  for i := 1 to Length(Path) do
    if (Path[i] = '*') or (Path[i] = '?') then cut := -1;
  if cut = 0 then
  begin
    st^.oneShot := True;
    if FindFillOne(st, Path, ExtractFileName(Path), Rslt) then
      FindFirst := 0
    else
      FindClose(Rslt);
    Exit;
  end;

  { Split at the last separator: everything up to and including it is the
    directory to open, the rest is the mask. }
  cut := 0;
  for i := 1 to Length(Path) do
    if Path[i] = '/' then cut := i;
  st^.dirPrefix := Copy(Path, 1, cut);
  st^.mask := Copy(Path, cut + 1, Length(Path) - cut);
  if st^.dirPrefix = '' then openDir := './' else openDir := st^.dirPrefix;

  st^.fd := PalOpen(PChar(openDir), PAL_OPEN_READ or PAL_OPEN_DIRECTORY, 0);
  if st^.fd < 0 then
  begin
    FindClose(Rslt);
    Exit;
  end;
  FindFirst := FindNext(Rslt);
  if FindFirst <> 0 then FindClose(Rslt);
end;

function ExecutePipeline(const cmd: AnsiString; const args: array of AnsiString; var childStdinFd, childStdoutFd: Integer): Integer;
const
  O_CLOEXEC = 524288;   { 0o2000000 -- create the pipe fds close-on-exec so a
                          LATER child's exec does not keep an EARLIER child's
                          pipes open. Without this, spawning a 2nd concurrent
                          child (e.g. audio alongside video) leaks the 1st
                          child's stdin write-end into it, so the 1st child never
                          sees EOF and wait() deadlocks. dup2 in the child clears
                          CLOEXEC on the wired-up fds, so 0/1 survive the exec. }
var
  stdinPipe: array[0..1] of Integer;
  stdoutPipe: array[0..1] of Integer;
  pid: Integer;
  argv: array of PChar;
  i: Integer;
  res: Integer;
  envp: Pointer;
begin
  stdinPipe[0] := -1; stdinPipe[1] := -1;
  stdoutPipe[0] := -1; stdoutPipe[1] := -1;

  { Construct argv in the parent process, before vfork! }
  SetLength(argv, Length(args) + 2);
  argv[0] := PChar(cmd);
  for i := 0 to Length(args) - 1 do
    argv[i + 1] := PChar(args[i]);
  argv[Length(args) + 1] := nil;

  { The child inherits OUR environment. Built here, in the parent, because it
    may read /proc/self/environ on first use and after vfork the child must not
    do I/O. }
  envp := EnvironmentBlock;

  if childStdinFd = -1 then
  begin
    if PalPipe2(stdinPipe, O_CLOEXEC) < 0 then
    begin
      Result := -1;
      Exit;
    end;
  end;

  if childStdoutFd = -1 then
  begin
    if PalPipe2(stdoutPipe, O_CLOEXEC) < 0 then
    begin
      if stdinPipe[0] <> -1 then
      begin
        res := PalClose(stdinPipe[0]);
        res := PalClose(stdinPipe[1]);
      end;
      Result := -1;
      Exit;
    end;
  end;

  { Fork and exec via PAL helper to avoid stack corruption }
  pid := PalVforkAndExec(PChar(cmd), @argv[0], envp, stdinPipe[0], stdinPipe[1], stdoutPipe[0], stdoutPipe[1]);

  if pid < 0 then
  begin
    { error }
    if stdinPipe[0] <> -1 then begin res := PalClose(stdinPipe[0]); res := PalClose(stdinPipe[1]); end;
    if stdoutPipe[0] <> -1 then begin res := PalClose(stdoutPipe[0]); res := PalClose(stdoutPipe[1]); end;
    Result := -1;
    Exit;
  end;

  { Parent process }
  { Close the ends of the pipes we don't need }
  if stdinPipe[0] <> -1 then
  begin
    res := PalClose(stdinPipe[0]); { Close child's read end }
    childStdinFd := stdinPipe[1]; { Parent writes here }
  end;

  if stdoutPipe[1] <> -1 then
  begin
    res := PalClose(stdoutPipe[1]); { Close child's write end }
    childStdoutFd := stdoutPipe[0]; { Parent reads from here }
  end;

  Result := pid;
end;

{ Howard Hinnant's public-domain "days_from_civil" / "civil_from_days"
  algorithm (proleptic Gregorian calendar, days since 1970-01-01), chosen
  over the classic FPC DivMod-table implementation because it is small
  enough to re-derive and verify from scratch rather than recall from
  memory, and because its era/yoe split is specifically designed to stay
  correct under ordinary truncating (round-toward-zero) integer division --
  exactly this dialect's `div`/`mod` semantics -- for negative (pre-epoch)
  inputs too. TDateTime's epoch (1899-12-30) is applied as a constant day
  offset from 1970-01-01, computed once via this same function so any
  internal convention only has to be self-consistent, not independently
  correct. Verified against real FPC SysUtils.DecodeDate/EncodeDate output
  across leap years, month/year boundaries, and pre-1899 dates. }
function DaysFromCivil(y, m, d: Int64): Int64;
var era, yoe, doy, doe: Int64;
begin
  if m <= 2 then y := y - 1;
  if y >= 0 then era := y div 400 else era := (y - 399) div 400;
  yoe := y - era * 400;                                      { [0, 399] }
  if m > 2 then doy := (153 * (m - 3) + 2) div 5 + d - 1
  else doy := (153 * (m + 9) + 2) div 5 + d - 1;              { [0, 365] }
  doe := yoe * 365 + yoe div 4 - yoe div 100 + doy;           { [0, 146096] }
  Result := era * 146097 + doe - 719468;                      { days since 1970-01-01 }
end;

procedure CivilFromDays(z: Int64; var y, m, d: Int64);
var era, doe, yoe, doy, mp: Int64;
begin
  z := z + 719468;
  if z >= 0 then era := z div 146097 else era := (z - 146096) div 146097;
  doe := z - era * 146097;                                            { [0, 146096] }
  yoe := (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365; { [0, 399] }
  y := yoe + era * 400;
  doy := doe - (365 * yoe + yoe div 4 - yoe div 100);                 { [0, 365] }
  mp := (5 * doy + 2) div 153;                                        { [0, 11] }
  d := doy - (153 * mp + 2) div 5 + 1;                                { [1, 31] }
  if mp < 10 then m := mp + 3 else m := mp - 9;                       { [1, 12] }
  if m <= 2 then y := y + 1;
end;

function EncodeDate(Year, Month, Day: Word): TDateTime;
begin
  Result := DaysFromCivil(Year, Month, Day) - DaysFromCivil(1899, 12, 30);
end;

procedure DecodeDate(aDate: TDateTime; out Year, Month, Day: Word);
var y, m, d: Int64;
begin
  CivilFromDays(Trunc(aDate) + DaysFromCivil(1899, 12, 30), y, m, d);
  Year := y; Month := m; Day := d;
end;

function EncodeTime(Hour, Min, Sec, MSec: Word): TDateTime;
begin
  Result := (Hour * 3600000 + Min * 60000 + Sec * 1000 + MSec) / 86400000.0;
end;

function IsLeapYear(Year: Word): Boolean;
begin
  Result := ((Year mod 4 = 0) and (Year mod 100 <> 0)) or (Year mod 400 = 0);
end;

function IncMonth(const DateTime: TDateTime; NumberOfMonths: Integer): TDateTime;
var
  y, m, d: Word;
  total, ny, nm: Int64;
  maxDay: Word;
  frac: TDateTime;
begin
  DecodeDate(DateTime, y, m, d);
  { Months since year 0, so the arithmetic is one number and the year rolls out
    of it. Pascal's div/mod truncate toward zero, which is wrong for negative
    totals (a date before year 0 is not reachable through Word years, but the
    same trap bites any large negative NumberOfMonths), so floor them by hand. }
  total := Int64(y) * 12 + Int64(m) - 1 + NumberOfMonths;
  ny := total div 12;
  nm := total mod 12;
  if nm < 0 then
  begin
    nm := nm + 12;
    ny := ny - 1;
  end;
  nm := nm + 1;
  maxDay := MonthDays[IsLeapYear(Word(ny))][Integer(nm)];
  if d > maxDay then d := maxDay;
  { Keep the time-of-day: Trunc/Frac split rather than re-encoding it, so no
    rounding is introduced by a round trip through EncodeTime. }
  frac := DateTime - Trunc(DateTime);
  Result := EncodeDate(Word(ny), Word(nm), d) + frac;
end;

procedure DateTimeToSystemTime(DateTime: TDateTime; out SystemTime: TSystemTime);
begin
  DecodeDate(DateTime, SystemTime.Year, SystemTime.Month, SystemTime.Day);
  DecodeTime(DateTime, SystemTime.Hour, SystemTime.Minute, SystemTime.Second,
             SystemTime.MilliSecond);
  { 1..7 from the function, 0..6 in the field -- FPC's own `Dec(...)`. }
  SystemTime.DayOfWeek := Word(DayOfWeek(DateTime) - 1);
end;

function SystemTimeToDateTime(const SystemTime: TSystemTime): TDateTime;
var
  d, t: TDateTime;
begin
  d := EncodeDate(SystemTime.Year, SystemTime.Month, SystemTime.Day);
  t := EncodeTime(SystemTime.Hour, SystemTime.Minute, SystemTime.Second,
                  SystemTime.MilliSecond);
  { FPC's ComposeDateTime, NOT `d + t`. Before the epoch the integer part runs
    negative while the time-of-day fraction is always positive, so adding them
    moves the clock BACKWARDS through the day: 1899-12-29 06:00 is -1 + 0.25 =
    -0.75, which decodes as 18:00 on the wrong side. dateutils' EncodeDateTime
    in this tree still adds, and sysutils' own DecodeDate notes carry the -0.75
    worked example; this routine takes the sign-correct form because a
    TSystemTime carries no indication that its date is pre-1900. }
  if d < 0 then Result := Trunc(d) - Abs(Frac(t))
  else Result := Trunc(d) + Abs(Frac(t));
end;

procedure GetLocalTime(var SystemTime: TSystemTime);
begin
  DateTimeToSystemTime(Now, SystemTime);
end;

function DayOfWeek(DateTime: TDateTime): Integer;
begin
  { Pascal mod truncates toward zero, so pre-epoch dates come out <= 0 and
    get folded back into 1..7. }
  Result := 1 + ((Trunc(DateTime) - 1) mod 7);
  if Result <= 0 then Result := Result + 7;
end;

{ zero-padded decimal of exactly width digits (enough for date fields) }
function PadNum(v: Integer; width: Integer): string;
var t: string;
begin
  t := IntToStr(v);
  while Length(t) < width do t := '0' + t;
  Result := t;
end;


function Now: TDateTime;
var
  sec, nsec: Int64;
begin
  Result := 0;
  if PalRealtime(sec, nsec) <> 0 then Exit;
  Result := UnixDateDelta + (sec + nsec / 1000000000.0) / 86400.0;
end;

function Date: TDateTime;
begin
  Result := Trunc(Now);
end;

function Time: TDateTime;
begin
  Result := Frac(Now);
end;

function DateTimeToTimeStamp(DateTime: TDateTime): TTimeStamp;
var
  h, mi, s, ms: Word;
begin
  DecodeTime(DateTime, h, mi, s, ms);
  Result.Time := Integer(h) * 3600000 + Integer(mi) * 60000 + Integer(s) * 1000 + ms;
  Result.Date := Trunc(DateTime) + DateDelta;
end;

function DateToStr(Date: TDateTime): string;
begin
  { FPC: FormatDateTime('ddddd', Date), and 'ddddd' IS ShortDateFormat. Passing
    the setting straight through is the same operation with one indirection
    fewer — and it keeps working whatever the caller has set the format to. }
  Result := FormatDateTime(ShortDateFormat, Date);
end;

function TimeToStr(Time: TDateTime): string;
begin
  Result := FormatDateTime(LongTimeFormat, Time);
end;

function DateTimeToStr(DateTime: TDateTime; ForceTimeIfZero: Boolean): string;
var
  h, mi, s, ms: Word;
begin
  Result := FormatDateTime(ShortDateFormat, DateTime);
  DecodeTime(DateTime, h, mi, s, ms);
  { FPC's 'c' omits the time half at exact midnight. Note the test is on
    h/mi/s only — MSec is deliberately NOT consulted, matching FPC. }
  if ForceTimeIfZero or (h <> 0) or (mi <> 0) or (s <> 0) then
    Result := Result + ' ' + FormatDateTime(LongTimeFormat, DateTime);
end;

function DateTimeToStr(DateTime: TDateTime): string;
begin
  Result := DateTimeToStr(DateTime, False);
end;

function GetTickCount64: Int64;
begin
  Result := PalMonotonicMillis;
end;

function GetTickCount: LongWord;
begin
  { deprecated in FPC, and this is why: the 32-bit truncation wraps. Kept
    bit-for-bit the same truncation so code that already copes with the wrap
    sees what it expects. }
  Result := LongWord(GetTickCount64 and $FFFFFFFF);
end;

function FileGetDate(Handle: Integer): Integer;
var info: TPalFileStat;
begin
  if PalFstat(Handle, info) <> 0 then
    Result := -1
  else
    Result := Integer(info.MTimeSec);
end;

function FileAge(const FileName: string): Int64;
var info: TPalFileStat;
begin
  { A DIRECTORY IS -1, not its mtime. Same shape as FileExists just below,
    which is also False for a directory -- one rule, two callers. }
  if (PalStat(PChar(FileName), info) <> 0) or info.IsDir then
    Result := -1
  else
    Result := info.MTimeSec;
end;

function FileDateToDateTime(FileDate: Int64): TDateTime;
begin
  { One linear conversion, not a date/time COMPOSITION -- so the pre-epoch sign
    trap that DateTimeToSystemTime has to handle does not arise here. A negative
    FileDate is a pre-1970 file and divides correctly. }
  Result := UnixDateDelta + FileDate / 86400.0;
end;

function DateTimeToFileDate(DateTime: TDateTime): Int64;
begin
  { Round, not Trunc: Trunc would bias every conversion towards the epoch --
    down for later times and UP for pre-epoch ones -- so a round trip through
    the pair would drift in opposite directions on either side of 1970. }
  Result := Round((DateTime - UnixDateDelta) * 86400.0);
end;

function TextToFloat(Buffer: PChar; var Value: Extended): Boolean;
begin
  { TryStrToFloat already carries the measured contract (trim, reject trailing
    junk, reject empty) — this is the PChar spelling of the same question, not
    a second parser. }
  Result := TryStrToFloat(StrPas(Buffer), Value);
end;

{ ---- environment ---------------------------------------------------------- }

var
  EnvLoaded: Boolean;
  EnvVars: array[0..1023] of string;   { each entry a whole NAME=VALUE record }
  EnvCount: Integer;
  { The block exactly as /proc/self/environ gave it. Kept because its records
    are ALREADY the NUL-terminated `NAME=VALUE` strings execve's envp wants, so
    a child's environment is pointers into this rather than a second copy. }
  EnvRaw: array[0..16383] of Char;
  EnvpTable: array[0..1024] of PChar;  { execve envp: one per record, then nil }

procedure EnvLoad;
{ Read /proc/self/environ once, through the PAL: its records are NUL-separated,
  so it is not text and this unit's text I/O cannot read it. A failure to open
  leaves the table empty, which reads back as "every variable is unset" rather
  than as an error — a program that cannot see its environment should behave
  like one started without one. }
var h, i, start, recStart: Integer; got: Int64; cur: string;
begin
  if EnvLoaded then Exit;
  EnvLoaded := True;
  EnvCount := 0;
  EnvpTable[0] := nil;                { an empty envp is still a valid envp }
  h := PalOpen(PChar('/proc/self/environ'), 0, 0);   { O_RDONLY }
  if h < 0 then Exit;
  got := PalRead(h, @EnvRaw[0], SizeOf(EnvRaw));
  PalClose(h);
  if got <= 0 then Exit;
  start := 0;
  i := 0;
  while i < got do
  begin
    if EnvRaw[i] = #0 then
    begin
      if i > start then
      begin
        recStart := start;
        cur := '';
        while start < i do
        begin
          cur := cur + EnvRaw[start];
          Inc(start);
        end;
        if EnvCount < 1024 then
        begin
          EnvVars[EnvCount] := cur;
          { the #0 just found terminates this record in place }
          EnvpTable[EnvCount] := @EnvRaw[recStart];
          Inc(EnvCount);
          EnvpTable[EnvCount] := nil;
        end;
      end;
      start := i + 1;
    end;
    Inc(i);
  end;
end;

{ Point the execve table at the CURRENT records. Rebuilt at use rather than
  maintained incrementally: the entries are pointers into Pascal strings, and a
  string reassigned by a write can move, so a table cached across a mutation
  could dangle. At most 1024 pointer stores. }
procedure EnvRebuildTable;
var i: Integer;
begin
  for i := 0 to EnvCount - 1 do EnvpTable[i] := PChar(EnvVars[i]);
  EnvpTable[EnvCount] := nil;
end;

{ Index of the record whose NAME is `name`, or -1. Compares up to the '=' so
  'PATH' does not match 'PATHEXT'. }
function EnvIndexOf(const name: string): Integer;
var i, j, n: Integer; rec: string; hit: Boolean;
begin
  EnvIndexOf := -1;
  n := Length(name);
  if n = 0 then Exit;
  for i := 0 to EnvCount - 1 do
  begin
    rec := EnvVars[i];
    if Length(rec) >= n + 1 then
      if rec[n + 1] = '=' then
      begin
        hit := True;
        for j := 1 to n do
          if rec[j] <> name[j] then begin hit := False; break; end;
        if hit then
        begin
          EnvIndexOf := i;
          Exit;
        end;
      end;
  end;
end;

procedure SetEnvironmentVariable(const name, value: string);
var idx: Integer;
begin
  if name = '' then Exit;
  EnvLoad;
  idx := EnvIndexOf(name);
  if idx >= 0 then
    EnvVars[idx] := name + '=' + value
  else if EnvCount < 1024 then
  begin
    EnvVars[EnvCount] := name + '=' + value;
    EnvCount := EnvCount + 1;
  end;
end;

procedure UnsetEnvironmentVariable(const name: string);
var idx, i: Integer;
begin
  if name = '' then Exit;
  EnvLoad;
  idx := EnvIndexOf(name);
  if idx < 0 then Exit;
  { compact: order carries no meaning in an environment }
  for i := idx to EnvCount - 2 do EnvVars[i] := EnvVars[i + 1];
  EnvCount := EnvCount - 1;
end;

function EnvironmentBlock: Pointer;
{ The parent's own environment shaped as execve's `envp`.

  Every spawn site used to hard-code an empty envp, so a pxx-compiled program
  handed each child `env -i` — no PATH, no HOME, no TZ — even when it never
  touched the environment itself. Nothing errored; the child just behaved as if
  started with nothing.

  Call this in the PARENT, before vfork: it may do I/O on first use, and after
  vfork the child must not. The pointers are into the global record strings,
  which are never freed, so they stay valid through the child's exec (which
  shares this address space until it execs). Rebuilt on every call so a write
  made since the last spawn is included. }
begin
  EnvLoad;
  EnvRebuildTable;
  EnvironmentBlock := @EnvpTable[0];
end;

const
  EXEC_MAX_ARGS = 256;   { argv slots, argv[0] and the nil terminator included }

type
  TExecArgv = array[0..EXEC_MAX_ARGS - 1] of PChar;

procedure RaiseExecuteProcessFailed(const Path: AnsiString; code: Longint);
{ fpc raises EOSError with the failing code in ErrorCode for both outcomes, and
  its message is SExecuteProcessFailed, 'Failed to execute %s : %d'. }
var e: EOSError;
begin
  e := EOSError.CreateFmt('Failed to execute %s : %d', [Path, code]);
  e.ErrorCode := code;
  raise e;
end;

function ExecuteProcessArgv(const Path: AnsiString; var argv: TExecArgv): Integer;
{ The shared tail of both overloads: spawn, wait, convert, raise.

  PalVforkAndExec skips any fd given as -1, so four -1s leave the child with
  every handle inherited — which is what ExecInheritsHandles asks for, and why
  Flags needs no consulting to be honoured in the only case it can express.

  The exit code is read the way a shell reads it, from the status word's high
  byte, which is the same conversion Popen.wait in subprocess.pas does. }
var pid, status: Integer;
begin
  pid := PalVforkAndExec(PChar(Path), @argv[0], EnvironmentBlock, -1, -1, -1, -1);
  ExecuteProcessArgv := -1;
  if pid = -1 then
  begin
    RaiseExecuteProcessFailed(Path, -1);
    Exit;
  end;
  status := 0;
  if PalWait4(pid, @status, 0, nil) > 0 then
    ExecuteProcessArgv := (status shr 8) and 255;
  if (ExecuteProcessArgv < 0) or (ExecuteProcessArgv = 127) then
    RaiseExecuteProcessFailed(Path, ExecuteProcessArgv);
end;

function ExecuteProcess(const Path: AnsiString; const ComLine: AnsiString;
                        Flags: TExecuteFlags = []): Integer;
{ The QUOTE-NAIVE form, and deliberately so — see the interface header. fpc's
  own compiler deprecates this overload in cfileutl.pas:142 for exactly the
  limitation reproduced here, so a faithful splitter is a whitespace splitter.

  argv[0] IS THE PATH AND NO WORD OF ComLine IS LOST — measured against fpc
  3.2.2, which is the only reason this is right. Reading
  rtl/unix/sysutils.pp:1631 alone suggests otherwise: `cmdline2^ :=
  PAnsiChar(LPath)` looks like it overwrites the first word. It does not.
  `StringtoPPChar(CommandLine, 1)` RESERVES one leading slot, so the store fills
  that reserve and every split word shifts up by one. The first version here
  dropped word 0 and printed `hello` where fpc prints `x hello`. }
var argv: TExecArgv;
    parts: array[0..EXEC_MAX_ARGS - 1] of AnsiString;
    n, i, j: Integer;
begin
  n := 0;
  i := 1;
  while (i <= Length(ComLine)) and (n < EXEC_MAX_ARGS - 2) do
  begin
    while (i <= Length(ComLine)) and (ComLine[i] <= ' ') do Inc(i);
    if i > Length(ComLine) then Break;
    j := i;
    while (j <= Length(ComLine)) and (ComLine[j] > ' ') do Inc(j);
    parts[n] := Copy(ComLine, i, j - i);
    Inc(n);
    i := j;
  end;
  argv[0] := PChar(Path);
  for i := 0 to n - 1 do argv[i + 1] := PChar(parts[i]);
  argv[n + 1] := nil;
  ExecuteProcess := ExecuteProcessArgv(Path, argv);
end;

function ExecuteProcess(const Path: AnsiString; const ComLine: array of AnsiString;
                        Flags: TExecuteFlags = []): Integer;
{ The form a program should reach for: argv goes through untouched, so a
  parameter containing a space or a quote arrives as ONE argument. }
var argv: TExecArgv;
    i, n: Integer;
begin
  n := Length(ComLine);
  if n > EXEC_MAX_ARGS - 2 then n := EXEC_MAX_ARGS - 2;
  argv[0] := PChar(Path);
  for i := 0 to n - 1 do argv[i + 1] := PChar(ComLine[i]);
  argv[n + 1] := nil;
  ExecuteProcess := ExecuteProcessArgv(Path, argv);
end;

function GetEnvironmentVariableCount: Integer;
begin
  EnvLoad;
  GetEnvironmentVariableCount := EnvCount;
end;

function GetEnvironmentString(Index: Integer): string;
begin
  EnvLoad;
  { FPC numbers these from 1 }
  if (Index >= 1) and (Index <= EnvCount) then GetEnvironmentString := EnvVars[Index - 1]
  else GetEnvironmentString := '';
end;

function GetEnvironmentVariable(const Name: string): string;
var i, j, n: Integer; rec, acc: string; matched: Boolean;
begin
  GetEnvironmentVariable := '';
  if Name = '' then Exit;
  EnvLoad;
  n := Length(Name);
  for i := 0 to EnvCount - 1 do
  begin
    rec := EnvVars[i];
    if Length(rec) > n then
      if rec[n + 1] = '=' then
      begin
        matched := True;
        for j := 1 to n do
          if rec[j] <> Name[j] then begin matched := False; Break; end;
        if matched then
        begin
          acc := '';
          for j := n + 2 to Length(rec) do acc := acc + rec[j];
          GetEnvironmentVariable := acc;
          Exit;
        end;
      end;
  end;
end;

function FileExists(const FileName: string): Boolean;
var info: TPalFileStat;
begin
  Result := (PalStat(PChar(FileName), info) = 0) and not info.IsDir;
end;

function DirectoryExists(const Dir: string): Boolean;
var info: TPalFileStat;
begin
  Result := (PalStat(PChar(Dir), info) = 0) and info.IsDir;
end;

function DeleteFile(const FileName: string): Boolean;
begin
  Result := PalDelete(PChar(FileName)) = 0;
end;

function CreateDir(const NewDir: string): Boolean;
begin
  { 0o777 — the kernel applies the process umask, same as FPC's fpMkdir. }
  Result := PalMkdir(PChar(NewDir), 511) = 0;
end;

function RemoveDir(const Dir: string): Boolean;
begin
  Result := PalRmdir(PChar(Dir)) = 0;
end;

function SetCurrentDir(const NewDir: string): Boolean;
begin
  Result := PalChdir(PChar(NewDir)) = 0;
end;

procedure GetDir(DriveNr: Byte; var Dir: AnsiString);
begin
  { DriveNr is ignored, not validated: fpc answers the cwd for ANY value on
    unix -- measured, GetDir(3, s) equals GetDir(0, s) -- so refusing a
    non-zero drive would reject code fpc accepts, for a parameter that means
    nothing on this target. }
  Dir := GetCurrentDir;
end;

function GetCurrentDir: string;
var
  buf: array[0..4095] of Char;
  n: Integer;
begin
  { PalGetcwd is the raw syscall: the byte count INCLUDING the NUL on success,
    -errno on failure. Anything <= 0 means we have no path — return '' rather
    than a buffer of uninitialised stack. }
  n := PalGetcwd(@buf[0], SizeOf(buf));
  if n <= 0 then
    Result := ''
  else
    Result := StrPas(@buf[0]);
end;

function RenameFile(const OldName, NewName: string): Boolean;
begin
  Result := PalRename(PChar(OldName), PChar(NewName)) = 0;
end;

function ForceDirectories(const Dir: string): Boolean;
var
  i, n: Integer;
  part: string;
begin
  { True when the whole path already exists — this is the idempotent member of
    the family, unlike CreateDir, which reports EEXIST as failure. }
  Result := False;
  if Dir = '' then Exit;
  n := Length(Dir);
  { walk the separators left to right, creating each missing prefix. A prefix
    that exists is not an error; only a prefix we can neither find nor create
    fails the whole call. }
  i := 1;
  while i <= n do
  begin
    if (Dir[i] = '/') and (i > 1) then
    begin
      part := Copy(Dir, 1, i - 1);
      if not DirectoryExists(part) then
        if not CreateDir(part) then
        begin
          { lost a race, or a real failure — only the second is fatal }
          if not DirectoryExists(part) then Exit;
        end;
    end;
    Inc(i);
  end;
  if Dir[n] <> '/' then
  begin
    if not DirectoryExists(Dir) then
      if not CreateDir(Dir) then
      begin
        Result := DirectoryExists(Dir);
        Exit;
      end;
  end;
  Result := DirectoryExists(Dir);
end;

function ExpandFileName(const FileName: string): string;
var
  s, seg, acc: string;
  i, n, segStart: Integer;
  trailing, uncRoot: Boolean;
begin
  s := FileName;
  if (s = '') or (s[1] <> '/') then
  begin
    { relative — anchor on the cwd. GetCurrentDir has no trailing slash, so one
      is added here; the empty input therefore expands to cwd + '/', which is
      what FPC gives (measured: ExpandFileName('') in /tmp is '/tmp/'). }
    acc := GetCurrentDir;
    if (acc = '') or (acc[Length(acc)] <> '/') then acc := acc + '/';
    s := acc + s;
  end;

  { A trailing separator on the INPUT survives expansion — FPC keeps it
    ('/a/b/' stays '/a/b/'), and callers that append a file name depend on it. }
  n := Length(s);
  trailing := (n > 0) and (s[n] = '/');

  { A path beginning with EXACTLY two slashes keeps them. POSIX reserves '//'
    for an implementation-defined meaning and forbids collapsing it, and FPC
    preserves it (measured: ExpandFileName('//a//b') = '//a/b', where every
    other run of slashes collapses). Three or more collapse to one. }
  uncRoot := (n >= 2) and (s[1] = '/') and (s[2] = '/') and
             ((n = 2) or (s[3] <> '/'));

  { Purely lexical collapse of '.', '..' and repeated separators. No stat, no
    symlink resolution — matching FPC, which expands paths that do not exist. }
  Result := '';
  i := 1;
  while i <= n do
  begin
    while (i <= n) and (s[i] = '/') do Inc(i);
    segStart := i;
    while (i <= n) and (s[i] <> '/') do Inc(i);
    if i > segStart then
    begin
      seg := Copy(s, segStart, i - segStart);
      if seg = '.' then
        { drop }
      else if seg = '..' then
      begin
        { pop one component; '..' at the root stays at the root, as in POSIX }
        if Result <> '' then
          Result := Copy(Result, 1, LastDelimiter('/', Result) - 1);
      end
      else
        Result := Result + '/' + seg;
    end;
  end;
  if Result = '' then
    Result := '/'
  else
  begin
    if uncRoot then Result := '/' + Result;
    if trailing then Result := Result + '/';
  end;
end;

function GetTempDir: string;
begin
  Result := '/tmp/';
end;


function GetTempFileName(const Dir, Prefix: string): string;
var
  base: string;
  n: Integer;
begin
  if Dir = '' then base := GetTempDir else base := Dir;
  if (Length(base) > 0) and (base[Length(base)] <> '/') then
    base := base + '/';
  if Prefix = '' then base := base + 'TMP' else base := base + Prefix;
  { seed from the monotonic clock so restarts don't retrace old names }
  n := Integer(PalMonotonicMillis mod 100000);
  repeat
    Result := base + IntToStr(n);
    Inc(n);
  until not FileExists(Result);
end;

function AdjustLineBreaks(const S: AnsiString; Style: TTextLineBreakStyle): AnsiString;
var
  i: Integer;
  nl: AnsiString;
begin
  case Style of
    tlbsCRLF: nl := #13#10;
    tlbsCR:   nl := #13;
  else
    nl := #10;
  end;
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if S[i] = #13 then
    begin
      Result := Result + nl;
      if (i < Length(S)) and (S[i + 1] = #10) then Inc(i);
    end
    else if S[i] = #10 then
      Result := Result + nl
    else
      Result := Result + S[i];
    Inc(i);
  end;
end;

function AdjustLineBreaks(const S: AnsiString): AnsiString;
begin
  Result := AdjustLineBreaks(S, tlbsLF);
end;

procedure SetString(var S: AnsiString; Buf: PChar; Len: Integer);
var i: Integer;
begin
  if Len < 0 then Len := 0;
  SetLength(S, Len);
  if Buf = nil then Exit;
  for i := 1 to Len do
    S[i] := Buf[i - 1];
end;

{ Raises ECONVERTERROR, not a bare Exception: `on E: EConvertError do` is the
  handler every FPC/Delphi caller writes around a parse, and a bare Exception
  walks straight past it — the catch is there, it just never fires. The rest of
  this family (StrToInt, StrToInt64, StrToFloat, StrToQWord) already raises
  EConvertError; this one was the odd arm out.

  MILLISECONDS are accepted after a DecimalSeparator, as FPC does:
  StrToTime('13:05:09.250') is 13:05:09.250 there and used to raise here.

  It is a MILLISECOND FIELD, not a decimal fraction — measured, because the
  obvious reading is wrong: FPC gives '13:05:09.25' → **25** ms and
  '13:05:09.2' → **2** ms, where a decimal fraction would mean 250 and 200. So
  the digits are read as a plain integer, at most three of them ('.1234'
  RAISES rather than truncating), and only after a full h:m:s ('13:05.5'
  raises).
  ([[bug-b-strtotime-raises-the-wrong-class-and-rejects-milliseconds]]) }
function TryStrToTime(const S: string; var Value: TDateTime): Boolean;
var
  part: array[0..2] of Integer;
  np, i, v, digits, ms, msDigits: Integer;
  c: Char;
  inFrac: Boolean;
begin
  { Every rejection is `Exit` with Result already False. The raising arm
    (StrToTime) is a two-line wrapper over this, so the two cannot answer
    differently — which is the failure mode this family kept having. }
  Result := False;
  { cleared on failure, not left alone: FPC declares these OUT params and a
    failed TryStrTo* is observably 0 there, so code that prints the variable
    without checking the Boolean sees the same thing on both. Measured. }
  Value := 0.0;
  part[0] := 0; part[1] := 0; part[2] := 0;
  np := 0;
  v := 0;
  digits := 0;
  ms := 0; msDigits := 0; inFrac := False;
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if (c >= '0') and (c <= '9') then
    begin
      if inFrac then
      begin
        ms := ms * 10 + (Ord(c) - Ord('0'));
        msDigits := msDigits + 1;
        if msDigits > 3 then Exit;     { FPC rejects a 4th digit }
      end
      else
      begin
        v := v * 10 + (Ord(c) - Ord('0'));
        digits := digits + 1;
      end;
    end
    else if (c = TimeSeparator) and (np < 2) and (digits > 0) and (not inFrac) then
    begin
      part[np] := v;
      np := np + 1;
      v := 0;
      digits := 0;
    end
    else if (c = DecimalSeparator) and (not inFrac) and (digits > 0)
            and (np = 2) then       { only after h:m:s, as FPC requires }
      inFrac := True
    else if c <> ' ' then
      Exit;
  end;
  if digits = 0 then Exit;
  if inFrac and (msDigits = 0) then Exit;
  part[np] := v;
  if (part[0] > 23) or (part[1] > 59) or (part[2] > 59) then Exit;
  Value := EncodeTime(part[0], part[1], part[2], ms);
  Result := True;
end;

function StrToTime(const S: string): TDateTime;
begin
  if not TryStrToTime(S, Result) then
    { FPC's exact wording — "is not a valid time", not "is an invalid time",
      which is what the integer arms say. Callers match on message text. }
    raise EConvertError.CreateFmt('"%s" is not a valid time', [S]);
end;

{ ParseDate results. The two failure classes are not cosmetic: FPC gives a
  different message for each, and a caller that greps the message sees them. }
const
  dpOK      = 0;
  dpFormat  = 1;   { does not scan as a date at all -> quoted message }
  dpInvalid = 2;   { scans, but the fields name no real day -> 'Invalid date' }

function ParseDate(const S: string; var Value: TDateTime): Integer;
var
  fld, fdig: array[0..2] of Integer;
  order: array[0..2] of Char;
  nf, i, k, v, digits, st, en, no, yd: Integer;
  y, mo, d, base: Integer;
  cy, cmo, cd: Word;
  c: Char;
  sy, sm, sd: Boolean;
begin
  Result := dpFormat;
  st := 1; en := Length(S);
  while (st <= en) and (S[st] = ' ') do st := st + 1;
  while (en >= st) and (S[en] = ' ') do en := en - 1;
  if st > en then Exit;

  { scan digit runs separated by DateSeparator; anything else is not a date.
    A TRAILING separator is tolerated ('14-08-2026-' parses) but a fourth
    field is not — both measured. }
  nf := 0; v := 0; digits := 0;
  for i := st to en do
  begin
    c := S[i];
    if (c >= '0') and (c <= '9') then
    begin
      v := v * 10 + (Ord(c) - Ord('0'));
      digits := digits + 1;
      if digits > 4 then Exit;
    end
    else if c = DateSeparator then
    begin
      if (digits = 0) or (nf > 2) then Exit;
      fld[nf] := v; fdig[nf] := digits; nf := nf + 1;
      v := 0; digits := 0;
    end
    else
      Exit;
  end;
  if digits > 0 then
  begin
    if nf > 2 then Exit;
    fld[nf] := v; fdig[nf] := digits; nf := nf + 1;
  end;
  if nf = 0 then Exit;

  { field order = the order the y/m/d letters first appear in ShortDateFormat,
    so 'd/m/y' and 'dd/mm/yyyy' behave alike. A format naming fewer than three
    of them cannot order anything, so fall back to FPC's default. }
  no := 0; sy := False; sm := False; sd := False;
  for i := 1 to Length(ShortDateFormat) do
  begin
    c := ShortDateFormat[i];
    if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    if (c = 'y') and (not sy) then begin order[no] := 'y'; no := no + 1; sy := True; end
    else if (c = 'm') and (not sm) then begin order[no] := 'm'; no := no + 1; sm := True; end
    else if (c = 'd') and (not sd) then begin order[no] := 'd'; no := no + 1; sd := True; end;
  end;
  if no < 3 then
  begin
    order[0] := 'd'; order[1] := 'm'; order[2] := 'y';
  end;

  { fields not given default to TODAY, which is why a bare '15' is the 15th of
    the current month. }
  DecodeDate(Date, cy, cmo, cd);
  y := cy; mo := cmo; d := cd; yd := 4;
  for k := 0 to nf - 1 do
    case order[k] of
      'y': begin y := fld[k]; yd := fdig[k]; end;
      'm': mo := fld[k];
      'd': d := fld[k];
    end;

  { sliding two-digit-year window: the 100 years ending TwoDigitYearCenturyWindow
    years before today, rounded down to a century. With window 50 in 2026 the
    low bound is 1976, so '49' is 2049 and '99' is 1999. }
  if yd <= 2 then
  begin
    base := ((cy - TwoDigitYearCenturyWindow) div 100) * 100;
    y := base + y;
    if y < (cy - TwoDigitYearCenturyWindow) then y := y + 100;
  end;

  if (mo < 1) or (mo > 12) or (y < 1) or (y > 9999) then
  begin
    Result := dpInvalid;
    Exit;
  end;
  if (d < 1) or (d > MonthDays[IsLeapYear(Word(y))][mo]) then
  begin
    Result := dpInvalid;
    Exit;
  end;
  Value := EncodeDate(Word(y), Word(mo), Word(d));
  Result := dpOK;
end;

function TryStrToDate(const S: string; var Value: TDateTime): Boolean;
begin
  Value := 0.0;                 { see TryStrToTime }
  Result := ParseDate(S, Value) = dpOK;
end;

procedure RaiseDateError(code: Integer; const S: string);
begin
  if code = dpInvalid then
    raise EConvertError.Create('Invalid date')
  else
    raise EConvertError.CreateFmt('"%s" is not a valid date format', [S]);
end;

function StrToDate(const S: string): TDateTime;
var code: Integer;
begin
  code := ParseDate(S, Result);
  if code <> dpOK then RaiseDateError(code, S);
end;

{ Split "<date> <time>" on whitespace. A lone token is a TIME if it contains
  TimeSeparator and a DATE otherwise, which is how FPC decides — and why
  StrToDateTime('x') complains about a date and not a time. }
procedure SplitDateTime(const S: string; var ds, ts: string);
var st, en, i, sp: Integer;
begin
  st := 1; en := Length(S);
  while (st <= en) and ((S[st] = ' ') or (S[st] = #9)) do st := st + 1;
  while (en >= st) and ((S[en] = ' ') or (S[en] = #9)) do en := en - 1;
  sp := 0;
  for i := st to en do
    if (S[i] = ' ') or (S[i] = #9) then begin sp := i; Break; end;
  ds := ''; ts := '';
  if sp > 0 then
  begin
    ds := Copy(S, st, sp - st);
    ts := Trim(Copy(S, sp, en - sp + 1));
  end
  else if Pos(TimeSeparator, Copy(S, st, en - st + 1)) > 0 then
    ts := Copy(S, st, en - st + 1)
  else
    ds := Copy(S, st, en - st + 1);
end;

function TryStrToDateTime(const S: string; var Value: TDateTime): Boolean;
var ds, ts: string; dv, tv: TDateTime;
begin
  SplitDateTime(S, ds, ts);
  dv := 0.0; tv := 0.0;
  Value := 0.0;                 { see TryStrToTime }
  Result := False;
  { time half FIRST — FPC validates it before the date, and it shows in which
    half a mixed-up string is blamed on ('12:34:56 14-08-2026' complains that
    the right-hand token is not a valid TIME). Order is observable here. }
  if ts <> '' then
    if not TryStrToTime(ts, tv) then Exit;
  if ds <> '' then
    if ParseDate(ds, dv) <> dpOK then Exit;
  if (ds = '') and (ts = '') then Exit;
  Value := dv + tv;
  Result := True;
end;

function StrToDateTime(const S: string): TDateTime;
var ds, ts: string; dv, tv: TDateTime; code: Integer;
begin
  SplitDateTime(S, ds, ts);
  dv := 0.0; tv := 0.0;
  if (ds = '') and (ts = '') then RaiseDateError(dpFormat, S);
  { time half first — see TryStrToDateTime }
  if ts <> '' then
    if not TryStrToTime(ts, tv) then
      raise EConvertError.CreateFmt('"%s" is not a valid time', [ts]);
  if ds <> '' then
  begin
    code := ParseDate(ds, dv);
    if code <> dpOK then RaiseDateError(code, ds);
  end;
  Result := dv + tv;
end;

function FormatDateTime(const Fmt: string; DateTime: TDateTime): string;
var
  y, mo, d, h, mi, sec, ms: Word;
  i, n, runLen: Integer;
  c, q, lo: Char;
begin
  DecodeDate(DateTime, y, mo, d);
  DecodeTime(DateTime, h, mi, sec, ms);
  Result := '';
  i := 1;
  n := Length(Fmt);
  while i <= n do
  begin
    c := Fmt[i];
    if (c = '"') or (c = #39) then
    begin
      { quoted literal: copied verbatim to the closing quote }
      q := c;
      Inc(i);
      while (i <= n) and (Fmt[i] <> q) do
      begin
        Result := Result + Fmt[i];
        Inc(i);
      end;
      if i <= n then Inc(i);   { closing quote }
    end
    else
    begin
      lo := c;
      if (lo >= 'A') and (lo <= 'Z') then lo := Chr(Ord(lo) + 32);
      if (lo = 'y') or (lo = 'm') or (lo = 'd') or (lo = 'h') or
         (lo = 'n') or (lo = 's') or (lo = 'z') then
      begin
        { token run: count same-letter repeats (case-insensitive) }
        runLen := 0;
        while i + runLen <= n do
        begin
          q := Fmt[i + runLen];
          if (q >= 'A') and (q <= 'Z') then q := Chr(Ord(q) + 32);
          if q <> lo then Break;
          runLen := runLen + 1;
        end;
        case lo of
          'y': if runLen >= 3 then Result := Result + PadNum(y, 4)
               else Result := Result + PadNum(y mod 100, 2);
          'm': if runLen >= 2 then Result := Result + PadNum(mo, 2)
               else Result := Result + IntToStr(mo);
          'd': if runLen >= 2 then Result := Result + PadNum(d, 2)
               else Result := Result + IntToStr(d);
          'h': if runLen >= 2 then Result := Result + PadNum(h, 2)
               else Result := Result + IntToStr(h);
          'n': if runLen >= 2 then Result := Result + PadNum(mi, 2)
               else Result := Result + IntToStr(mi);
          's': if runLen >= 2 then Result := Result + PadNum(sec, 2)
               else Result := Result + IntToStr(sec);
          'z': if runLen >= 3 then Result := Result + PadNum(ms, 3)
               else Result := Result + IntToStr(ms);
        end;
        i := i + runLen;
      end
      else if c = '/' then
      begin
        { '/' is not a literal slash: Delphi and FPC define it as "the date
          separator character", so it renders whatever DateSeparator holds.
          Measured against FPC 3.2.2 — with DateSeparator '.',
          FormatDateTime('dd/mm/yy') gives 14.08.26, where this returned
          14/08/26 whatever the setting was. A caller that sets the separator
          for a locale got its format string ignored.
          ([[bug-b-formatdatetime-emits-slash-and-colon-literally]]) }
        Result := Result + DateSeparator;
        Inc(i);
      end
      else if c = ':' then
      begin
        { likewise TimeSeparator. This one LOOKED correct only because the
          default happens to be ':' — with TimeSeparator '_', FPC gives
          13_05_09 and this still gave 13:05:09. }
        Result := Result + TimeSeparator;
        Inc(i);
      end
      else
      begin
        Result := Result + c;
        Inc(i);
      end;
    end;
  end;
end;

procedure DecodeTime(aTime: TDateTime; out Hour, Min, Sec, MSec: Word);
var frac: Double; totalMSec: Int64;
begin
  { Matches real FPC/Delphi exactly (verified empirically, not assumed): the
    date part truncates toward zero (Trunc, same as DecodeDate), and the
    time-of-day part is the ABSOLUTE VALUE of the leftover fraction -- e.g.
    EncodeDate(1899,12,29) + EncodeTime(6,0,0,0) = -0.75 decodes to
    1899-12-30 18:00 in real FPC, not 1899-12-29 06:00 as a naive floor-
    based split would give. }
  frac := Abs(aTime - Trunc(aTime));
  totalMSec := Round(frac * 86400000.0);
  if totalMSec >= 86400000 then totalMSec := totalMSec - 86400000;  { rounding at the day boundary }
  Hour := totalMSec div 3600000;
  totalMSec := totalMSec mod 3600000;
  Min := totalMSec div 60000;
  totalMSec := totalMSec mod 60000;
  Sec := totalMSec div 1000;
  MSec := totalMSec mod 1000;
end;


function CompareMem(P1, P2: Pointer; Len: Int64): Boolean;
var a, b: PChar; i: Int64;
begin
  a := PChar(P1);
  b := PChar(P2);
  CompareMem := True;
  for i := 0 to Len - 1 do
    if a[i] <> b[i] then
    begin
      CompareMem := False;
      Exit;
    end;
end;

function CompareMemRange(P1, P2: Pointer; Len: Int64): Integer;
var a, b: PByte; i: Int64;
begin
  a := PByte(P1);
  b := PByte(P2);
  CompareMemRange := 0;
  for i := 0 to Len - 1 do
    if a[i] <> b[i] then
    begin
      if a[i] < b[i] then CompareMemRange := -1 else CompareMemRange := 1;
      Exit;
    end;
end;

function DynArraySize(P: Pointer): Int64;
begin
  if P = nil then
    DynArraySize := 0
  else
    DynArraySize := PInt64(PtrUInt(P) - 8)^;
end;

function SysBackTraceStr(Addr: Pointer): string;
begin
  Result := '  $' + IntToHex(PtrUInt(Addr), 2 * SizeOf(Pointer));
end;

function ExceptAddr: Pointer;
begin
  { The raise stub records the raise site (the return address its `call` pushed) in
    the exception-address BSS slot; __pxxExceptAddr is the compiler intrinsic that
    reads it. nil when no exception is in flight. }
  Result := __pxxExceptAddr;
end;

function ExceptObject: TObject;
begin
  { The twin of ExceptAddr: the raise stub parks the object itself in the
    exception-object BSS slot -- the very slot `on E: T do` loads to bind its
    handler variable -- and __pxxExceptObject reads it. The intrinsic is untyped
    on purpose, so the cast to TObject happens HERE, where TObject exists, rather
    than in the parser. nil when no exception is in flight. }
  Result := TObject(__pxxExceptObject);
end;

procedure SysAssertError(const msg: AnsiString);
begin
  { Installed into builtin's AssertErrorProc below, mirroring FPC: System's
    default prints and run-errors 227, and SysUtils REPLACES it with one that
    raises, which is what makes `try Assert(...) except` able to run its
    handler. Same ErrorProc design as the overflow/div-zero/range hooks beside
    this one. compat-pascal-assert-halts-instead-of-raising-eassertionfailed }
  if msg = '' then
    raise EAssertionFailed.Create('Assertion failed')
  else
    raise EAssertionFailed.Create(msg);
end;

procedure SysRaiseOverflow;
begin
  { {$Q+} overflow trap upgraded to a catchable exception — installed into
    builtinheap's PXXOverflowHook below, mirroring FPC's ErrorProc design
    (feature-pascal-overflow-checks-q-plus). }
  raise EIntOverflow.Create('Arithmetic overflow');
end;

procedure SysRaiseRangeError;
begin
  { {$R+} range trap upgraded to a catchable exception
    (feature-pascal-range-checks-r-plus). }
  raise ERangeError.Create('Range check error');
end;

procedure SysRaiseIoError;
begin
  { {$I+} Text-I/O failure upgraded to a catchable exception
    (feature-pascal-io-checks-i-plus). }
  raise EInOutError.Create('I/O error');
end;

procedure SysRaiseDivByZero;
begin
  { Integer div/mod by zero upgraded from Runtime error 200 to a catchable
    EDivByZero when sysutils is in — the PXXDivZeroHook slot existed for
    exactly this and was never wired (tint642's testreqword catches it). }
  raise EDivByZero.Create('Division by zero');
end;

procedure SysRaiseVariantError(const msg: AnsiString);
begin
  { A failed Variant conversion upgraded from print-and-Halt(219) to a
    catchable exception. FPC catches `try i := v; except on E: Exception`
    here and the program continues; pxx used to die inside the helper, which
    made the ordinary "parse it, fall back if it isn't a number" shape
    impossible to write. bug-a-variant-conversion-failure-is-uncatchable }
  raise EVariantError.Create(msg);
end;

procedure SysRaiseInvalidCast;
begin
  { A failed `as` downcast upgraded from a silent Halt to a catchable
    exception. It was the only member of the checked-operation family that
    `try ... except` could not intercept, which is exactly backwards for the
    one construct whose purpose is a downcast you are prepared to have fail.
    bug-a-a-failed-as-downcast-dies-silently-and-uncatchably }
  raise EInvalidCast.Create('Invalid type cast');
end;

procedure SysRaiseAccessViolation;
begin
  { A nil receiver / nil procvar call, caught at the site by the compiler's
    emitted check, upgraded to a catchable exception. EAccessViolation has been
    declared since the exception hierarchy landed and had nothing to raise it
    until now (feature-a-emitted-nil-checks). }
  raise EAccessViolation.Create('Access violation (nil reference)');
end;


{ ---- TStringHelper — Delphi's method-style string surface ----------------
  Every routine here delegates to the intrinsic or to this unit's own function,
  self-qualified as `sysutils.X` because the helper method shadows the global
  of the same name and an unqualified call would recurse. All index arithmetic
  converts between Delphi's 0-based convention and Pascal's 1-based one at the
  boundary; see the declaration's table for the fpc-derived values. }

function TStringHelper.GetLength: SizeInt;
begin
  GetLength := System.Length(Self);
end;

function TStringHelper.IsEmpty: Boolean;
begin
  IsEmpty := System.Length(Self) = 0;
end;

function TStringHelper.ToUpper: AnsiString;
begin
  ToUpper := sysutils.UpperCase(Self);
end;

function TStringHelper.ToLower: AnsiString;
begin
  ToLower := sysutils.LowerCase(Self);
end;

function TStringHelper.Trim: AnsiString;
begin
  Trim := sysutils.Trim(Self);
end;

function TStringHelper.TrimLeft: AnsiString;
begin
  TrimLeft := sysutils.TrimLeft(Self);
end;

function TStringHelper.TrimRight: AnsiString;
begin
  TrimRight := sysutils.TrimRight(Self);
end;

{ 0-based start. A start past the end yields '' and a negative one clamps to 0
  -- fpc answers '' for 'abc'.Substring(9) and 'abc' for 'abc'.Substring(-1),
  neither of which is an error. }
function TStringHelper.Substring(AStartIndex: SizeInt): AnsiString;
begin
  Substring := Self.Substring(AStartIndex, System.Length(Self));
end;

function TStringHelper.Substring(AStartIndex: SizeInt; ALen: SizeInt): AnsiString;
begin
  if AStartIndex < 0 then AStartIndex := 0;
  if ALen < 0 then ALen := 0;
  Substring := Copy(Self, AStartIndex + 1, ALen);
end;

{ 0-based, and -1 when absent -- Pos is 1-based and 0 when absent, so the
  conversion is the same subtraction in both cases and needs no special case. }
function TStringHelper.IndexOf(const AValue: AnsiString): SizeInt;
begin
  IndexOf := sysutils.Pos(AValue, Self) - 1;
end;

function TStringHelper.IndexOf(const AValue: AnsiString; StartIndex: SizeInt): SizeInt;
var tail: AnsiString; p: SizeInt;
begin
  if StartIndex < 0 then StartIndex := 0;
  tail := Copy(Self, StartIndex + 1, System.Length(Self));
  p := sysutils.Pos(AValue, tail);
  if p = 0 then IndexOf := -1
  else IndexOf := p - 1 + StartIndex;
end;

function TStringHelper.LastIndexOf(const AValue: AnsiString): SizeInt;
var i, n, m: SizeInt;
begin
  LastIndexOf := -1;
  n := System.Length(Self);
  m := System.Length(AValue);
  if (m = 0) or (m > n) then Exit;
  for i := n - m + 1 downto 1 do
    if Copy(Self, i, m) = AValue then
    begin
      LastIndexOf := i - 1;
      Exit;
    end;
end;

function TStringHelper.StartsWith(const AValue: AnsiString): Boolean;
begin
  StartsWith := Copy(Self, 1, System.Length(AValue)) = AValue;
end;

function TStringHelper.EndsWith(const AValue: AnsiString): Boolean;
var n, m: SizeInt;
begin
  n := System.Length(Self);
  m := System.Length(AValue);
  EndsWith := (m <= n) and (Copy(Self, n - m + 1, m) = AValue);
end;

function TStringHelper.Contains(const AValue: AnsiString): Boolean;
begin
  Contains := sysutils.Pos(AValue, Self) > 0;
end;

{ FPC's two-argument Replace replaces EVERY occurrence: 'a-b-a'.Replace('a','X')
  is 'X-b-X', not 'X-b-a'. }
function TStringHelper.Replace(const OldValue, NewValue: AnsiString): AnsiString;
begin
  Replace := sysutils.StringReplace(Self, OldValue, NewValue, [rfReplaceAll]);
end;

function TStringHelper.Replace(const OldValue, NewValue: AnsiString; Flags: TReplaceFlags): AnsiString;
begin
  Replace := sysutils.StringReplace(Self, OldValue, NewValue, Flags);
end;

{ Splitting '' yields ONE empty element, not zero, and adjacent separators yield
  an empty element between them -- 'a,,b' is three parts. }
function TStringHelper.Split(const Separators: array of Char): TStringArray;
var i, j, n, cnt: SizeInt; isSep: Boolean; cur: AnsiString;
begin
  n := System.Length(Self);
  SetLength(Split, 0);
  cnt := 0;
  cur := '';
  for i := 1 to n do
  begin
    isSep := False;
    for j := 0 to High(Separators) do
      if Self[i] = Separators[j] then isSep := True;
    if isSep then
    begin
      SetLength(Split, cnt + 1);
      Split[cnt] := cur;
      cnt := cnt + 1;
      cur := '';
    end
    else
      cur := cur + Self[i];
  end;
  SetLength(Split, cnt + 1);
  Split[cnt] := cur;
end;

{ Never truncates: padding to a width the string already exceeds returns it
  unchanged. }
function TStringHelper.PadLeft(ATotalWidth: SizeInt): AnsiString;
begin
  PadLeft := Self.PadLeft(ATotalWidth, ' ');
end;

function TStringHelper.PadLeft(ATotalWidth: SizeInt; PaddingChar: Char): AnsiString;
var i, n: SizeInt; pad: AnsiString;
begin
  n := System.Length(Self);
  if n >= ATotalWidth then begin PadLeft := Self; Exit; end;
  pad := '';
  for i := 1 to ATotalWidth - n do pad := pad + PaddingChar;
  PadLeft := pad + Self;
end;

function TStringHelper.PadRight(ATotalWidth: SizeInt): AnsiString;
begin
  PadRight := Self.PadRight(ATotalWidth, ' ');
end;

function TStringHelper.PadRight(ATotalWidth: SizeInt; PaddingChar: Char): AnsiString;
var i, n: SizeInt; pad: AnsiString;
begin
  n := System.Length(Self);
  if n >= ATotalWidth then begin PadRight := Self; Exit; end;
  pad := '';
  for i := 1 to ATotalWidth - n do pad := pad + PaddingChar;
  PadRight := Self + pad;
end;


initialization
  DefaultSystemCodePage := CP_UTF8;   { byte-transparent -- see the declaration }
  BackTraceStrFunc := @SysBackTraceStr;
  AssertErrorProc := @SysAssertError;
  PXXOverflowHook := @SysRaiseOverflow;
  PXXDivZeroHook := @SysRaiseDivByZero;
  PXXRangeErrorHook := @SysRaiseRangeError;
  PXXIoErrorHook := @SysRaiseIoError;
  PXXNilRefHook := @SysRaiseAccessViolation;
  PXXInvalidCastHook := @SysRaiseInvalidCast;
  PXXVariantErrorHook := @SysRaiseVariantError;
  TimeSeparator := ':';
  DateSeparator := '-';
  ShortDateFormat := 'd/m/y';
  LongTimeFormat := 'hh:nn:ss';
  ShortTimeFormat := 'hh:nn';
  LongDateFormat := 'dd" "mmmm" "yyyy';
  TwoDigitYearCenturyWindow := 50;
  DecimalSeparator := '.';
  ThousandSeparator := ',';
  CurrencyString := '$';
  CurrencyFormat := 1;
  NegCurrFormat := 5;
  CurrencyDecimals := 2;
  ShortMonthNames[1] := 'Jan';  ShortMonthNames[2] := 'Feb';
  ShortMonthNames[3] := 'Mar';  ShortMonthNames[4] := 'Apr';
  ShortMonthNames[5] := 'May';  ShortMonthNames[6] := 'Jun';
  ShortMonthNames[7] := 'Jul';  ShortMonthNames[8] := 'Aug';
  ShortMonthNames[9] := 'Sep';  ShortMonthNames[10] := 'Oct';
  ShortMonthNames[11] := 'Nov'; ShortMonthNames[12] := 'Dec';
  LongMonthNames[1] := 'January';   LongMonthNames[2] := 'February';
  LongMonthNames[3] := 'March';     LongMonthNames[4] := 'April';
  LongMonthNames[5] := 'May';       LongMonthNames[6] := 'June';
  LongMonthNames[7] := 'July';      LongMonthNames[8] := 'August';
  LongMonthNames[9] := 'September'; LongMonthNames[10] := 'October';
  LongMonthNames[11] := 'November'; LongMonthNames[12] := 'December';
  ShortDayNames[1] := 'Sun'; ShortDayNames[2] := 'Mon'; ShortDayNames[3] := 'Tue';
  ShortDayNames[4] := 'Wed'; ShortDayNames[5] := 'Thu'; ShortDayNames[6] := 'Fri';
  ShortDayNames[7] := 'Sat';
  LongDayNames[1] := 'Sunday';    LongDayNames[2] := 'Monday';
  LongDayNames[3] := 'Tuesday';   LongDayNames[4] := 'Wednesday';
  LongDayNames[5] := 'Thursday';  LongDayNames[6] := 'Friday';
  LongDayNames[7] := 'Saturday';
end.
