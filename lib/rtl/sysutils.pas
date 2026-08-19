{ SPDX-License-Identifier: Zlib }
unit sysutils;
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

  TReplaceFlag  = (rfReplaceAll, rfIgnoreCase);
  TReplaceFlags = set of TReplaceFlag;

  { FPC SysUtils event-log severity (eventlog.pp et al). }
  TEventType  = (etCustom, etInfo, etWarning, etError, etDebug);
  TEventTypes = set of TEventType;

  PInt64Rec  = ^Int64;
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
  Exception = class(ExceptionBase)
    constructor Create(const msg: string);
    constructor CreateFmt(const msg: string; const args: array of const);
  end;

  { FPC System.TMethod: the two words a method pointer is made of. A `procedure of
    object` value has exactly this layout -- Code at +0, Data (Self) at +8 -- so code
    that builds a method pointer by hand fills a TMethod and casts it to the method
    type. fpcunit's TTestCase.RunBare does that to invoke a test method found by RTTI. }
  PMethod = ^TMethod;
  TMethod = record
    Code: Pointer;
    Data: Pointer;
  end;

  { FPC's standard SysUtils exception hierarchy. Real classes, not aliases: code catches them
    by type (`on E: EConvertError do`) and `is`/`as` must distinguish them, so each needs its
    own identity. Only the ones real code raises and catches are here; adding another is one
    line and no thought. }
  EAbort            = class(Exception) end;
  EConvertError     = class(Exception) end;      { StrToInt/StrToFloat on malformed input }
  EInOutError       = class(Exception) end;
  EAccessViolation  = class(Exception) end;
  EInvalidOp        = class(Exception) end;
  EIntError         = class(Exception) end;
  EDivByZero        = class(EIntError) end;
  ERangeError       = class(EIntError) end;
  EIntOverflow      = class(EIntError) end;
  EMathError        = class(Exception) end;
  EInvalidPointer   = class(Exception) end;
  EOutOfMemory      = class(Exception) end;
  EAssertionFailed  = class(Exception) end;
  ENotImplemented   = class(Exception) end;
  EArgumentException = class(Exception) end;
  EListError        = class(Exception) end;

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

{ FPC System.ExceptAddr: the address at which the CURRENT exception was raised.

  THIS RETURNS NIL TODAY, and that is a stub, not an implementation -- we do not record
  the raise site. It is declared because FPC code calls it, and because its callers are
  diagnostic: fpcunit feeds it to AddFailure, whose AddrsToStr prints 'n/a' for a nil
  address, so a nil lands on the unit's own sanctioned "no address known" path rather
  than lying with a plausible-looking pointer. Pass/fail is unaffected.

  The honest fix is cheap and filed (bug-pascal-exceptaddr-returns-nil): IR_RAISE
  already stores the exception object and class into BSS slots, and the CALL to the
  raise stub pushes the raise site itself -- so the address is right there to capture. }
function ExceptAddr: Pointer;

{ The default BackTraceStrFunc: '  $00000000004012AB'. A nil address renders as
  $0, which is what the callers' "no address known" path already expects. }
function SysBackTraceStr(Addr: Pointer): string;

{ Int64 -> decimal string (covers Integer via widening). Handles negatives. }
function IntToStr(value: Int64): AnsiString;

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
function StringOfChar(ch: Char; count: Integer): AnsiString;

{ 1-based substring; count clamped to the end; out-of-range index -> ''. }
function Copy(const s: AnsiString; index, count: Integer): AnsiString;

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
  placeholder: see UTF8Decode above, which is the identity for the same reason. }
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

  THIS RTL HAS ONE STRING MODEL: bytes. There is no UTF-16 UnicodeString to convert TO, so
  `UnicodeString` IS `string` here and these are the IDENTITY. That is stated rather than
  hidden, because it IS an approximation: FPC's UTF8Decode produces UTF-16 code units, and
  code that indexes the result expecting one element per CHARACTER will see one element per
  BYTE here. For ASCII -- which is what fpjson's JSON escaping actually walks -- the two agree
  exactly; for multi-byte UTF-8 they do not. Real UTF-16 is a string-model decision, not a
  function to bolt on. }
function UTF8Decode(const s: AnsiString): AnsiString;
function UTF8Encode(const s: AnsiString): AnsiString;

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
function FloatToStrF(value: Double; precision: Integer): AnsiString;

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

{ Currency <-> string. CurrToStr has existed in the implementation since the
  Currency type was added but was never declared here, so no caller outside
  this unit could reach it — `CurrToStr(c)` was an "undefined variable". }
function CurrToStr(C: Currency): AnsiString;
function StrToCurr(const s: AnsiString): Currency;
function StrToCurrDef(const s: AnsiString; def: Currency): Currency;

{ Return the position of substr in s, 1-based; 0 if not found. }
function Pos(const substr, s: AnsiString): Integer;

{ Null-terminated PChar routines (FPC's `strings` unit, re-exported by SysUtils).
  StrLCopy copies at most MaxLen chars from Source up to its #0, always #0-
  terminates Dest, and returns Dest. StrLComp compares at most MaxLen chars,
  returning <0 / 0 / >0 like FPC (stops at the first #0 or difference). }
{ True when the Len bytes at P1 and P2 are identical (FPC SysUtils.CompareMem). }
function CompareMem(P1, P2: Pointer; Len: Int64): Boolean;

function StrLCopy(Dest, Source: PChar; MaxLen: Cardinal): PChar;
function StrLComp(Str1, Str2: PChar; MaxLen: Cardinal): Integer;

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

{ Remove count chars from s starting at 1-based index. No-op if index < 1,
  index > Length(s), or count <= 0. Count is clamped to the end of s. }
procedure Delete(var s: AnsiString; index, count: Integer);

{ Insert src into dst at 1-based index. If index < 1, inserts at 1;
  if index > Length(dst)+1, appends. No-op if src is empty. }
procedure Insert(const src: AnsiString; var dst: AnsiString; index: Integer);

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
function SameText(const s1, s2: AnsiString): Boolean;
function AnsiSameText(const s1, s2: AnsiString): Boolean;

{ Strip leading / trailing chars <= ' '. }
function TrimLeft(const s: AnsiString): AnsiString;
function TrimRight(const s: AnsiString): AnsiString;

{ Parse a decimal integer; True + value on success, False (value untouched) on
  any malformed input. }
function TryStrToInt(const s: AnsiString; var value: Integer): Boolean;

{ Replace occurrences of OldPattern in S with NewPattern. rfReplaceAll replaces
  every occurrence (else only the first); rfIgnoreCase matches case-insensitively. }
function StringReplace(const S, OldPattern, NewPattern: AnsiString; Flags: TReplaceFlags): AnsiString;

{ Wrap s in single quotes, doubling any embedded quote. }
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

implementation

uses platform, platform_types, wideint;

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

function UTF8Decode(const s: AnsiString): AnsiString;
begin
  Result := s;      { identity -- see the declaration }
end;

function UTF8Encode(const s: AnsiString): AnsiString;
begin
  Result := s;
end;

{ The sentinel trick these three share: parse with two DIFFERENT defaults. A malformed input
  yields whichever default was asked for, so the two runs disagree; a well-formed input parses
  to the same value both times. That is cheaper and more honest than duplicating each
  parser's validation, and it cannot be fooled -- no single input can equal both sentinels. }
function TryStrToInt64(const s: AnsiString; var value: Int64): Boolean;
begin
  Result := ParseIntPrefixed(s, value);
end;

function TryStrToQWord(const s: AnsiString; var value: QWord): Boolean;
var a, b: QWord;
begin
  a := StrToQWordDef(s, 0);
  b := StrToQWordDef(s, 1);
  Result := (a = b);
  if Result then value := a;
end;

{ The single float parser; body far below, next to the exact-decimal
  machinery it uses. Forward-declared because the whole StrToFloat family
  up here is a wrapper over it. }
function ParseFloatCore(const s: AnsiString; var value: Double): Boolean; forward;

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

function StringOfChar(ch: Char; count: Integer): AnsiString;
var s: AnsiString; i: Integer;
begin
  s := '';
  for i := 1 to count do s := s + ch;
  Result := s;
end;

function Copy(const s: AnsiString; index, count: Integer): AnsiString;
var n, last, len: Integer;
begin
  n := Length(s);
  if index < 1 then index := 1;
  if count < 0 then count := 0;
  last := index + count - 1;
  if last > n then last := n;
  len := last - index + 1;
  if len <= 0 then begin Result := ''; Exit; end;
  { build the result once — SetLength + a single Move, not char-by-char append }
  SetLength(Result, len);
  Move(s[index], Result[1], len);
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

function SysNanosleepNo: Integer;
begin
  Result := -1;
  {$ifdef CPUX86_64} Result := 35;  {$endif}
  {$ifdef CPU_I386}  Result := 162; {$endif}
  {$ifdef CPU_AARCH64} Result := 101; {$endif}
  {$ifdef CPU_ARM32} Result := 162; {$endif}
end;

procedure Sleep(Milliseconds: Cardinal);
type
  TKernelTimeSpec = record Sec: NativeInt; Nsec: NativeInt; end;
var
  req: TKernelTimeSpec;
  n: Integer;
  res: Int64;
begin
  n := SysNanosleepNo;
  if n = -1 then Exit;
  req.Sec  := Milliseconds div 1000;
  req.Nsec := (Milliseconds mod 1000) * 1000000;
  res := __pxxrawsyscall(n, Int64(@req), 0, 0, 0, 0, 0);
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

{ ---- exact decimal expansion of a Double ---------------------------------

  THIS CORE IS COPIED. `compiler/builtin/pylib.pas` carries a renamed copy of
  everything from here down to ExDecRound, and of the correctly-rounded parser
  closure below (ExDecCmp .. StrToFloatDef), because a builtin unit may not
  `uses sysutils` — NilPy's unit scope is flat, so every name here would
  collide in every NilPy program. Moving the core down into a shared builtin
  unit was considered and rejected: library source has to stay STEPPABLE, and
  stepping into FloatToStr should not walk you out of this file
  (decide-nilpy-where-the-exact-decimal-float-core-lives).

  CHANGE ONE, CHANGE BOTH. `test/lib_floattostr.pas` pins this copy and
  `test/test_nilpy_float_repr.npy` pins the other, over a shared value table
  with CPython as the oracle, so a drift between them fails a test.

  Every finite double IS a finite decimal, exactly. value = mant * 2^exp2 with
  mant a 53-bit integer, and 2^-k = 5^k * 10^-k, so the exact decimal form is
  the integer mant*5^k with the point pushed k places left (k = -exp2). For
  exp2 >= 0 it is the plain integer mant*2^exp2. No approximation enters, so
  every digit produced is a real digit of the value — which is exactly what the
  normalise-in-doubles path in FloatToStrSig cannot do past 15, and why that
  routine caps there.

  Worst case is a denormal at exp2 = -1074: 5^1074 is 751 digits, times a
  16-digit mantissa, so 767 digits. Those live little-endian in limbs of nine
  decimal digits (base 10^9), grown by repeated multiply-by-small. Two chunk
  sizes do the scaling: 5^13 and 2^30, the largest powers whose per-limb
  product stays inside Int64 (10^9 * 5^13 is 1.2e18, well under 9.2e18). That
  turns the worst case into ~83 passes over ~86 limbs instead of 1074 passes
  over 767 single digits.

  Base 10^9 rather than one digit per byte is a ~9x cut in the inner loop, and
  it is the reason the exact path is affordable on BOTH sides: the decimal ->
  double search below expands a candidate per comparison, so expansion cost is
  multiplied by the search, not paid once. }
const
  PXX_EXDEC_LIMBS = 96;           { 9 digits each; 767 digits needs 86 }
  PXX_EXDEC_BASE  = 1000000000;   { 10^9 }
  PXX_EXDEC_P5_13 = 1220703125;   { 5^13 }
  PXX_EXDEC_P2_30 = 1073741824;   { 2^30 }
type
  TExDecBuf   = array[0..PXX_EXDEC_LIMBS - 1] of Int64;
  PExDecInt64 = ^Int64;

{ buf := buf * f. f is small enough that limb*f + carry cannot leave Int64. }
procedure ExDecMul(var buf: TExDecBuf; var n: Integer; f: Int64);
var i: Integer; t, carry: Int64;
begin
  carry := 0;
  for i := 0 to n - 1 do
  begin
    t := buf[i] * f + carry;
    buf[i] := t mod PXX_EXDEC_BASE;
    carry := t div PXX_EXDEC_BASE;
  end;
  while (carry > 0) and (n < PXX_EXDEC_LIMBS) do
  begin
    buf[n] := carry mod PXX_EXDEC_BASE;
    carry := carry div PXX_EXDEC_BASE;
    n := n + 1;
  end;
end;

{ Split a finite value into mant * 2^exp2 with mant an integer. Reads the
  IEEE-754 fields directly; a denormal carries no implicit leading bit. }
procedure ExDecSplit(value: Double; var mant: Int64; var exp2: Integer);
var bits, frac: Int64; be: Integer;
begin
  bits := PExDecInt64(@value)^;
  be   := Integer((bits shr 52) and $7FF);
  frac := bits and ((Int64(1) shl 52) - 1);
  if be = 0 then
  begin
    mant := frac;
    exp2 := -1074;
  end
  else
  begin
    mant := frac or (Int64(1) shl 52);
    exp2 := be - 1075;
  end;
end;

{ Exact digits of mant * 2^exp2: ds holds them most significant first with no
  leading zero, and decExp is the power of ten the first digit stands for (so
  267.5 gives '2675' and decExp = 2). Taking mant/exp2 rather than a Double is
  deliberate — the decimal->double side needs the exact expansion of MIDPOINTS
  between adjacent doubles, and a midpoint needs 54 bits, so it is not a
  Double. mant = 0 yields '0'. }
procedure ExDecOfMant(mant: Int64; exp2: Integer;
                      var ds: AnsiString; var decExp: Integer);
var
  buf: TExDecBuf;
  n, i, j, k, at, fracDigits: Integer;
  v: Int64;
  lp: AnsiString;
begin
  n := 0;
  while mant > 0 do
  begin
    buf[n] := mant mod PXX_EXDEC_BASE;
    mant := mant div PXX_EXDEC_BASE;
    n := n + 1;
  end;
  if n = 0 then begin buf[0] := 0; n := 1; end;
  fracDigits := 0;
  if exp2 >= 0 then
  begin
    k := exp2;
    while k >= 30 do begin ExDecMul(buf, n, PXX_EXDEC_P2_30); k := k - 30; end;
    while k > 0 do begin ExDecMul(buf, n, 2); k := k - 1; end;
  end
  else
  begin
    k := -exp2;
    fracDigits := k;
    while k >= 13 do begin ExDecMul(buf, n, PXX_EXDEC_P5_13); k := k - 13; end;
    while k > 0 do begin ExDecMul(buf, n, 5); k := k - 1; end;
  end;
  while (n > 1) and (buf[n - 1] = 0) do n := n - 1;
  { Top limb unpadded (that is what drops the leading zeros), the rest padded
    to the full nine so limb boundaries do not swallow interior zeros.

    Built into a string sized ONCE and filled by index. The obvious spelling —
    `ds := ds + lp` per limb, each limb zero-padded by `lp := '0' + lp` — is
    quadratic: it reallocates and recopies the whole accumulated prefix every
    limb, and a subnormal expands to ~765 digits (85 limbs). That was measured
    as the single largest cost in StrToFloat's exact path, which calls this
    about four times per parse: removing it took the mid-range case from 99 to
    30 us per value and subnormals from 2.78 ms to 1.22 ms
    (bug-b-strtofloat-is-3600x-slower-than-cpython-for-small-exponents).

    Digits are emitted low-to-high within each limb, which is why the inner
    loop walks j downwards into a slot whose base is already known. }
  lp := IntToStr(buf[n - 1]);
  SetLength(ds, Length(lp) + 9 * (n - 1));
  for i := 1 to Length(lp) do ds[i] := lp[i];
  at := Length(lp);
  for i := n - 2 downto 0 do
  begin
    v := buf[i];
    for j := 9 downto 1 do
    begin
      ds[at + j] := Chr(Ord('0') + Integer(v mod 10));
      v := v div 10;
    end;
    at := at + 9;
  end;
  decExp := Length(ds) - 1 - fracDigits;
end;

{ Exact digits of a finite Double, sign ignored. }
procedure ExDecDigits(value: Double; var ds: AnsiString; var decExp: Integer);
var mant: Int64; exp2: Integer;
begin
  ExDecSplit(value, mant, exp2);
  ExDecOfMant(mant, exp2, ds, decExp);
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

{ ---- decimal -> double, correctly rounded --------------------------------

  The old parser accumulated in doubles: one rounding per fractional digit, and
  10^e built by e successive multiplies (e up to 308, so the power itself was
  tens of ULP off). That is at most an approximation of the nearest double, and
  it is why exact 17-digit forms of 1/3, 1e-300, DBL_MAX and the denormals did
  not read back. Correct rounding means landing on the nearest double every
  time, so the value is reconstructed with the exact expansion above rather
  than with float arithmetic. }

{ Compare two exact decimals held as (digits, decExp) — digits most significant
  first with no leading zero, decExp the power of ten the first digit stands
  for. Both must be positive and nonzero. Shorter operands read as zero-padded,
  so '25'/1 and '250'/1 compare equal (both are 25). }
function ExDecCmp(const a: AnsiString; ae: Integer;
                  const b: AnsiString; be: Integer): Integer;
var i, n: Integer; ca, cb: Char;
begin
  if ae <> be then
  begin
    if ae < be then Result := -1 else Result := 1;
    Exit;
  end;
  n := Length(a);
  if Length(b) > n then n := Length(b);
  for i := 1 to n do
  begin
    if i <= Length(a) then ca := a[i] else ca := '0';
    if i <= Length(b) then cb := b[i] else cb := '0';
    if ca <> cb then
    begin
      if ca < cb then Result := -1 else Result := 1;
      Exit;
    end;
  end;
  Result := 0;
end;

function ExDecBitsToDouble(b: Int64): Double;
type PExDecDouble = ^Double;
begin
  Result := PExDecDouble(@b)^;
end;

function ExDecDoubleToBits(d: Double): Int64;
begin
  Result := PExDecInt64(@d)^;
end;

{ A cheap approximation of int(ds) * 10^expo. This is float arithmetic and is
  therefore wrong by some ULP — it is NEVER trusted, only used to seed the
  bracket for the exact search, which then proves the answer. Getting it close
  is purely a speed matter: the search costs one exact expansion per step, and
  seeding turns a 63-step search over the whole bit range into a handful of
  steps around the right answer. Powers of ten are applied by binary splitting
  (at most nine multiplies) rather than one per decade. }
function ExDecEstimate(const ds: AnsiString; nd, expo: Integer): Double;
var
  sig: Int64;
  i, k, e: Integer;
  w: Double;
  p10: array[0..8] of Double;
begin
  k := nd;
  if k > 17 then k := 17;
  sig := 0;
  for i := 1 to k do sig := sig * 10 + Int64(Ord(ds[i]) - Ord('0'));
  { digits we did not take are absorbed into the exponent }
  e := expo + (nd - k);
  w := sig * 1.0;
  p10[0] := 1.0e1;   p10[1] := 1.0e2;   p10[2] := 1.0e4;   p10[3] := 1.0e8;
  p10[4] := 1.0e16;  p10[5] := 1.0e32;  p10[6] := 1.0e64;  p10[7] := 1.0e128;
  p10[8] := 1.0e256;
  { the table spans 2^9-1 = 511 decades; anything past that is far outside the
    double range and only has to land on the correct side of it }
  if e > 511 then e := 511;
  if e < -511 then e := -511;
  if e > 0 then
  begin
    for i := 0 to 8 do
      if (e and (1 shl i)) <> 0 then w := w * p10[i];
  end
  else if e < 0 then
  begin
    k := -e;
    { divide rather than multiply by a negative power: keeps the intermediate
      from overflowing on the way down }
    for i := 0 to 8 do
      if (k and (1 shl i)) <> 0 then w := w / p10[i];
  end;
  Result := w;
end;

{ The double nearest to the positive decimal (ds, decExp), correctly rounded,
  ties to even.

  For positive doubles the IEEE bit pattern increases monotonically with the
  value, so "largest double <= D" is a plain ordered search over the bit
  pattern — 63 steps, each comparing D against the candidate's EXACT decimal
  expansion. There is no estimate here that could be wrong by an unknown number
  of ULP; the search cannot land anywhere but the right pair of neighbours.

  Then one decision between that double c and the next one up. Their midpoint is
  exactly (2*mant + 1) * 2^(exp2 - 1) — one formula that holds everywhere,
  including across a power-of-two boundary (where c = (2^53-1)*2^e and the next
  is 2^52*2^(e+1)) and across the denormal/normal boundary, because incrementing
  the bit pattern is exactly what both of those transitions are. The midpoint
  needs 54 bits, which is why the expansion above takes a mantissa rather than a
  Double.

  Out-of-range inputs fall out correctly rather than needing a guard: below the
  smallest denormal the search settles on bits 0 and the midpoint test rounds to
  zero, and above DBL_MAX it settles on DBL_MAX whose "next up" bit pattern is
  +Inf. }
function ExDecNearest(const ds: AnsiString; decExp, nd, expo: Integer): Double;
var
  lo, hi, mid, mant, maxbits, step, eb: Int64;
  exp2, cmp: Integer;
  cds, mds: AnsiString;
  cexp, mexp: Integer;
  c, est: Double;

  { sign of exact(bits) - D }
  function CmpBits(b: Int64): Integer;
  var d: Double; xs: AnsiString; xe: Integer;
  begin
    d := ExDecBitsToDouble(b);
    if b = 0 then begin CmpBits := -1; Exit; end;   { 0 < D, D is positive }
    ExDecDigits(d, xs, xe);
    CmpBits := ExDecCmp(xs, xe, ds, decExp);
  end;

begin
  { DBL_MAX = biased exponent 2046, mantissa all ones }
  maxbits := (Int64(2046) shl 52) or ((Int64(1) shl 52) - 1);

  { Seed from the float estimate, then widen by doubling steps until the
    bracket provably straddles D. The estimate's error is never assumed —
    if it is wildly wrong the doubling simply runs until it reaches the ends,
    which is the unseeded search and still correct. }
  est := ExDecEstimate(ds, nd, expo);
  if (est <> est) or (est >= 1.7976931348623157e308) then eb := maxbits
  else if est <= 0.0 then eb := 0
  else
  begin
    eb := ExDecDoubleToBits(est);
    if eb < 0 then eb := 0;
    if eb > maxbits then eb := maxbits;
  end;

  lo := eb;
  step := 1;
  while (lo > 0) and (CmpBits(lo) > 0) do
  begin
    lo := lo - step;
    if lo < 0 then lo := 0;
    step := step * 2;
  end;

  hi := eb;
  step := 1;
  while (hi < maxbits) and (CmpBits(hi) < 0) do
  begin
    hi := hi + step;
    if hi > maxbits then hi := maxbits;
    step := step * 2;
  end;

  { largest bit pattern whose exact value is <= D }
  while lo < hi do
  begin
    mid := lo + (hi - lo + 1) div 2;
    if CmpBits(mid) <= 0 then lo := mid else hi := mid - 1;
  end;

  c := ExDecBitsToDouble(lo);
  if lo <> 0 then
  begin
    ExDecDigits(c, cds, cexp);
    if ExDecCmp(cds, cexp, ds, decExp) = 0 then begin Result := c; Exit; end;
  end;

  ExDecSplit(c, mant, exp2);
  ExDecOfMant(2 * mant + 1, exp2 - 1, mds, mexp);
  cmp := ExDecCmp(ds, decExp, mds, mexp);
  if cmp > 0 then Result := ExDecBitsToDouble(lo + 1)
  else if cmp < 0 then Result := c
  else if (mant mod 2) = 0 then Result := c          { exact tie -> even }
  else Result := ExDecBitsToDouble(lo + 1);
end;

{ ---- decimal -> double, correctly rounded, compared in BINARY --------------

  The same question ExDecNearest answers, with the same guarantee — correctly
  rounded by construction, never an estimate that could be off by an unknown
  number of ULP — but comparing in binary big-integer arithmetic instead of
  expanding every candidate to its exact DECIMAL.

  WHY, AND WHY IT SITS BESIDE ExDecNearest RATHER THAN REPLACING IT.
  ExDecNearest's cost is not the number of comparisons (measured at ~4 per
  parse, not the 63 its header's worst case suggests) — it is the price of ONE.
  Each comparison expands a candidate double to its exact decimal, which for a
  subnormal is ~765 digits reached by ~82 rounds of big-decimal multiply, every
  round two 64-bit DIVISIONS per limb. Eisel-Lemire removed that cost for
  normal values but declines below the normal floor by construction, as Go and
  Rust do, so the subnormal rows of
  bug-b-strtofloat-is-3600x-slower-than-cpython-for-small-exponents never moved.

  In binary the same comparison is

      m * 2^k   ?   d * 10^expo

  and 10^expo = 2^expo * 5^expo, so every power of two becomes a SHIFT and only
  the power of five is a multiply. Better: d and expo are fixed for the whole
  search while only the candidate's m and k move, so 5^|expo| is built ONCE per
  parse instead of once per comparison.

  It DECLINES rather than guesses — the same composition as EiselLemire above.
  Every capacity check returns False and falls through to ExDecNearest, which is
  untouched and has no size limit. A buffer that turned out too small is
  therefore a slower answer, never a wrong one.

  Base 2^32 in Int64 limbs: a limb times any multiplier under 2^31, plus carry,
  stays inside a signed 64-bit product — which is what lets every routine here
  be plain Pascal with no 128-bit intermediate, on 32-bit targets too. }
const
  PXX_BIGF_LIMBS = 224;              { 7168 bits — see the bound in ExBinNearest }
  PXX_BIGF_MASK  = Int64($FFFFFFFF);
  PXX_BIGF_P5_13 = 1220703125;       { 5^13, the largest power of five under 2^31 }
type
  TBigF = array[0..PXX_BIGF_LIMBS - 1] of Int64;

procedure BigFNorm(var a: TBigF; var n: Integer);
begin
  while (n > 1) and (a[n - 1] = 0) do n := n - 1;
end;

procedure BigFCopy(const src: TBigF; sn: Integer; var dst: TBigF; var dn: Integer);
var i: Integer;
begin
  for i := 0 to sn - 1 do dst[i] := src[i];
  dn := sn;
end;

{ a := a * f. f must be under 2^31 so limb*f + carry cannot leave Int64. }
function BigFMulSmall(var a: TBigF; var n: Integer; f: Int64): Boolean;
var i: Integer; t, carry: Int64;
begin
  carry := 0;
  for i := 0 to n - 1 do
  begin
    t := a[i] * f + carry;
    a[i] := t and PXX_BIGF_MASK;
    carry := t shr 32;
  end;
  while carry > 0 do
  begin
    if n >= PXX_BIGF_LIMBS then begin BigFMulSmall := False; Exit; end;
    a[n] := carry and PXX_BIGF_MASK;
    carry := carry shr 32;
    n := n + 1;
  end;
  BigFNorm(a, n);                     { f = 0 leaves every limb zero }
  BigFMulSmall := True;
end;

function BigFAddSmall(var a: TBigF; var n: Integer; v: Int64): Boolean;
var i: Integer; t: Int64;
begin
  i := 0;
  while v > 0 do
  begin
    if i >= PXX_BIGF_LIMBS then begin BigFAddSmall := False; Exit; end;
    if i >= n then begin a[i] := 0; n := i + 1; end;
    t := a[i] + v;
    a[i] := t and PXX_BIGF_MASK;
    v := t shr 32;
    i := i + 1;
  end;
  BigFAddSmall := True;
end;

function BigFAdd(var a: TBigF; var na: Integer; const b: TBigF; nb: Integer): Boolean;
var i: Integer; t, carry: Int64;
begin
  BigFAdd := False;
  if nb > na then
  begin
    if nb > PXX_BIGF_LIMBS then Exit;
    for i := na to nb - 1 do a[i] := 0;
    na := nb;
  end;
  carry := 0;
  for i := 0 to na - 1 do
  begin
    t := a[i] + carry;
    if i < nb then t := t + b[i];
    a[i] := t and PXX_BIGF_MASK;
    carry := t shr 32;
  end;
  if carry > 0 then
  begin
    if na >= PXX_BIGF_LIMBS then Exit;
    a[na] := carry; na := na + 1;
  end;
  BigFAdd := True;
end;

function BigFShl(var a: TBigF; var n: Integer; bits: Integer): Boolean;
var words, b, i: Integer; t, carry: Int64;
begin
  BigFShl := False;
  if bits < 0 then Exit;
  if (n = 1) and (a[0] = 0) then begin BigFShl := True; Exit; end;
  b := bits mod 32;
  words := bits div 32;
  if b > 0 then
  begin
    carry := 0;
    for i := 0 to n - 1 do
    begin
      t := (a[i] shl b) or carry;
      a[i] := t and PXX_BIGF_MASK;
      carry := t shr 32;
    end;
    if carry > 0 then
    begin
      if n >= PXX_BIGF_LIMBS then Exit;
      a[n] := carry; n := n + 1;
    end;
  end;
  if words > 0 then
  begin
    if n + words > PXX_BIGF_LIMBS then Exit;
    for i := n - 1 downto 0 do a[i + words] := a[i];
    for i := 0 to words - 1 do a[i] := 0;
    n := n + words;
  end;
  BigFShl := True;
end;

{ a := a * v for v under 2^55 — the largest operand here is a midpoint's
  2*mant+1. Split into two sub-2^31 halves rather than reaching for a 128-bit
  product, so the same code serves 32-bit targets. }
function BigFMulU64(var a: TBigF; var n: Integer; v: Int64): Boolean;
var t: TBigF; tn: Integer; hi, lo: Int64;
begin
  BigFMulU64 := False;
  lo := v and ((Int64(1) shl 27) - 1);
  hi := v shr 27;
  if hi = 0 then begin BigFMulU64 := BigFMulSmall(a, n, lo); Exit; end;
  BigFCopy(a, n, t, tn);
  if not BigFMulSmall(a, n, lo) then Exit;
  if not BigFMulSmall(t, tn, hi) then Exit;
  if not BigFShl(t, tn, 27) then Exit;
  BigFMulU64 := BigFAdd(a, n, t, tn);
end;

{ a := a * 5^k, in place. Thirteen at a time: 5^13 is the largest power of five
  under 2^31, which is the cap BigFMulSmall's carry arithmetic needs. }
function BigFMulPow5(var a: TBigF; var n: Integer; k: Integer): Boolean;
begin
  BigFMulPow5 := False;
  if k < 0 then Exit;
  while k >= 13 do
  begin
    if not BigFMulSmall(a, n, PXX_BIGF_P5_13) then Exit;
    k := k - 13;
  end;
  while k > 0 do
  begin
    if not BigFMulSmall(a, n, 5) then Exit;
    k := k - 1;
  end;
  BigFMulPow5 := True;
end;

function BigFPow5(k: Integer; var a: TBigF; var n: Integer): Boolean;
begin
  a[0] := 1; n := 1;
  BigFPow5 := BigFMulPow5(a, n, k);
end;

{ Nine digits at a time: 10^9 is the largest power of ten under 2^31. }
function BigFFromDigits(const ds: AnsiString; nd: Integer;
                        var a: TBigF; var n: Integer): Boolean;
var i, j, chunk: Integer; v, p: Int64;
begin
  BigFFromDigits := False;
  a[0] := 0; n := 1;
  i := 1;
  while i <= nd do
  begin
    chunk := nd - i + 1;
    if chunk > 9 then chunk := 9;
    v := 0; p := 1;
    for j := 0 to chunk - 1 do
    begin
      v := v * 10 + Int64(Ord(ds[i + j]) - Ord('0'));
      p := p * 10;
    end;
    if not BigFMulSmall(a, n, p) then Exit;
    if not BigFAddSmall(a, n, v) then Exit;
    i := i + chunk;
  end;
  BigFFromDigits := True;
end;

function BigFCmp(const a: TBigF; na: Integer; const b: TBigF; nb: Integer): Integer;
var i: Integer;
begin
  if na <> nb then
  begin
    if na < nb then BigFCmp := -1 else BigFCmp := 1;
    Exit;
  end;
  for i := na - 1 downto 0 do
    if a[i] <> b[i] then
    begin
      if a[i] < b[i] then BigFCmp := -1 else BigFCmp := 1;
      Exit;
    end;
  BigFCmp := 0;
end;

{ Sign of (mv * 2^ev) - D, where D = int(ds) * 10^expo is carried in the two
  candidate-independent operands the caller built once:

    p5ta    = 5^ta                with ta = max(0, -expo)
    rhsBase = int(ds) * 5^tb      with tb = max(0,  expo)

  so the comparison is

      mv * 5^ta * 2^(SB+ta)   ?   int(ds) * 5^tb * 2^(SA+tb)

  with SA = max(0,-ev), SB = max(0,ev), after cancelling 2^min from both sides —
  free, and worth about a third of a subnormal's operand size, since its ev is
  -1074 and that shift alone is 1074 bits.

  `ok` is cleared if either operand would not fit, and the caller then declines
  to ExDecNearest. Top-level rather than nested inside ExBinNearest because a
  nested routine cannot capture a fixed-size array yet
  (feature-nested-routine-fixed-array-capture) — and both callers wanted the
  same body regardless. }
function BigFCmpValue(const p5ta: TBigF; p5n: Integer;
                      const rhsBase: TBigF; rhsn: Integer;
                      ta, tb: Integer; mv: Int64; ev: Integer;
                      var ok: Boolean): Integer;
var
  lhs, rhs: TBigF;
  ln, rn, sa, sb, e2l, e2r, cc: Integer;
begin
  BigFCmpValue := 0;
  if ev >= 0 then begin sa := 0; sb := ev; end
  else begin sa := -ev; sb := 0; end;
  e2l := sb + ta;
  e2r := sa + tb;
  if e2l < e2r then cc := e2l else cc := e2r;
  e2l := e2l - cc;
  e2r := e2r - cc;
  BigFCopy(p5ta, p5n, lhs, ln);
  if not BigFMulU64(lhs, ln, mv) then begin ok := False; Exit; end;
  if not BigFShl(lhs, ln, e2l) then begin ok := False; Exit; end;
  BigFCopy(rhsBase, rhsn, rhs, rn);
  if not BigFShl(rhs, rn, e2r) then begin ok := False; Exit; end;
  BigFCmpValue := BigFCmp(lhs, ln, rhs, rn);
end;

{ Sign of exact(bits) - D for a positive-double bit pattern. }
function BigFCmpBits(const p5ta: TBigF; p5n: Integer;
                     const rhsBase: TBigF; rhsn: Integer;
                     ta, tb: Integer; b: Int64; var ok: Boolean): Integer;
var mm: Int64; ex2: Integer;
begin
  if b = 0 then begin BigFCmpBits := -1; Exit; end;   { 0 < D, D is positive }
  ExDecSplit(ExDecBitsToDouble(b), mm, ex2);
  if mm = 0 then begin BigFCmpBits := -1; Exit; end;
  BigFCmpBits := BigFCmpValue(p5ta, p5n, rhsBase, rhsn, ta, tb, mm, ex2, ok);
end;

{ The double nearest the positive decimal int(ds) * 10^expo, correctly rounded,
  ties to even. False = declined; the caller must fall back to ExDecNearest.

  The search is ExDecNearest's, unchanged and for the same reason: for positive
  doubles the IEEE bit pattern rises monotonically with the value, so "largest
  double <= D" is an ordered search, seeded by a float estimate that is never
  trusted — only used to start the bracket, which then proves itself. What is
  different is the comparator, and only the comparator.

  The midpoint between a double and the next one up is exactly
  (2*mant + 1) * 2^(exp2 - 1) — one formula that holds across a power-of-two
  boundary and across the denormal/normal boundary alike, because incrementing
  the bit pattern is exactly what both of those transitions are.

  Out-of-range inputs fall out rather than needing a guard: below the smallest
  denormal the search settles on bits 0 and the midpoint test rounds to zero;
  above DBL_MAX it settles on DBL_MAX, whose next-up bit pattern is +Inf. }
function ExBinNearest(const ds: AnsiString; decExp, nd, expo: Integer;
                      var value: Double): Boolean;
var
  lo, hi, mid, mant, maxbits, step, eb: Int64;
  exp2, cmp, ta, tb: Integer;
  p5ta, rhsBase: TBigF;
  p5n, rhsn: Integer;
  cd, est: Double;
  ok: Boolean;
begin
  ExBinNearest := False;

  { Decline outside a few decades of the double range. Not a correctness guard
    — ExDecNearest answers those — but a SIZE one: an exponent like 1e-999999
    would ask for 5^999999, while the old path settles such a value in one or
    two comparisons anyway, because its estimate clamps straight to 0 or DBL_MAX
    and the bracket closes immediately. With decExp bounded here and nd bounded
    by the parser's 1200-digit cap, the largest operand either side can reach is
    about 6500 bits, inside the 7168 the limb array holds. Every routine above
    still range-checks, so an error in that bound costs a decline, not a wrong
    answer. }
  if (decExp > 400) or (decExp < -450) then Exit;
  if (nd < 1) or (nd > 1201) then Exit;

  if expo >= 0 then begin ta := 0; tb := expo; end
  else begin ta := -expo; tb := 0; end;

  { The two candidate-independent operands, built once for the whole search.
    int(ds) * 5^tb needs no big-by-big multiply — 5^tb is applied to the digits
    in place in sub-2^31 chunks, which is why only BigFMulSmall exists here. }
  if not BigFFromDigits(ds, nd, rhsBase, rhsn) then Exit;
  if not BigFMulPow5(rhsBase, rhsn, tb) then Exit;
  if not BigFPow5(ta, p5ta, p5n) then Exit;

  ok := True;
  { DBL_MAX = biased exponent 2046, mantissa all ones }
  maxbits := (Int64(2046) shl 52) or ((Int64(1) shl 52) - 1);

  est := ExDecEstimate(ds, nd, expo);
  if (est <> est) or (est >= 1.7976931348623157e308) then eb := maxbits
  else if est <= 0.0 then
  begin
    { The float estimate underflowed to zero — which happens for EVERY value
      below ~1e-308, i.e. exactly the subnormals this path exists for, so
      seeding at zero would be the common case and not the rare one. From zero
      the doubling walk climbs to the answer one power of two at a time (about
      44 steps for 1e-310) and the binary search then comes back down: ~90
      comparisons where a good seed needs a handful. Measured, before and after:
      1e-310 went 11.5 us -> 1.5 us on this line alone.

      So estimate it SCALED. A subnormal's bit pattern IS value * 2^1074, and
      2^1074 / 10^350 is itself an ordinary double (~2.02e-27), so

          bits ~ (d * 10^(expo+350)) * (2^1074 / 10^350)

      keeps both factors in the normal range. Still only a seed — nothing below
      trusts it, the bracket proves itself either way — so a value genuinely
      below the smallest subnormal simply underflows again and seeds 0, which is
      then correct rather than merely close. }
    est := ExDecEstimate(ds, nd, expo + 350) * 2.0240225330731063e-27;
    if (est <> est) or (est <= 0.0) then eb := 0
    else if est >= 4.5035996273704960e15 then eb := maxbits   { 2^52, past subnormal }
    else eb := Trunc(est);
  end
  else
  begin
    eb := ExDecDoubleToBits(est);
    if eb < 0 then eb := 0;
    if eb > maxbits then eb := maxbits;
  end;

  lo := eb;
  step := 1;
  while (lo > 0) and
        (BigFCmpBits(p5ta, p5n, rhsBase, rhsn, ta, tb, lo, ok) > 0) do
  begin
    if not ok then Exit;
    lo := lo - step;
    if lo < 0 then lo := 0;
    step := step * 2;
  end;
  if not ok then Exit;

  hi := eb;
  step := 1;
  while (hi < maxbits) and
        (BigFCmpBits(p5ta, p5n, rhsBase, rhsn, ta, tb, hi, ok) < 0) do
  begin
    if not ok then Exit;
    hi := hi + step;
    if hi > maxbits then hi := maxbits;
    step := step * 2;
  end;
  if not ok then Exit;

  { largest bit pattern whose exact value is <= D }
  while lo < hi do
  begin
    mid := lo + (hi - lo + 1) div 2;
    if BigFCmpBits(p5ta, p5n, rhsBase, rhsn, ta, tb, mid, ok) <= 0 then lo := mid
    else hi := mid - 1;
    if not ok then Exit;
  end;

  cd := ExDecBitsToDouble(lo);
  if lo <> 0 then
  begin
    cmp := BigFCmpBits(p5ta, p5n, rhsBase, rhsn, ta, tb, lo, ok);
    if not ok then Exit;
    if cmp = 0 then
    begin
      value := cd;
      ExBinNearest := True;
      Exit;
    end;
  end;

  ExDecSplit(cd, mant, exp2);
  { BigFCmpValue gives midpoint - D; the decision below wants D - midpoint }
  cmp := -BigFCmpValue(p5ta, p5n, rhsBase, rhsn, ta, tb, 2 * mant + 1, exp2 - 1, ok);
  if not ok then Exit;
  if cmp > 0 then value := ExDecBitsToDouble(lo + 1)
  else if cmp < 0 then value := cd
  else if (mant mod 2) = 0 then value := cd          { exact tie -> even }
  else value := ExDecBitsToDouble(lo + 1);
  ExBinNearest := True;
end;

function StrToFloatDef(const s: AnsiString; def: Double): Double;
begin
  if not ParseFloatCore(s, Result) then Result := def;
end;

{ The one parser. StrToFloatDef, TryStrToFloat and StrToFloat are all thin
  wrappers over it -- there is exactly one scan per call, and failure is a
  returned flag rather than an answer that has to be probed for. }

{ ---- Eisel-Lemire: the fast path for everything Clinger cannot reach ------

  Clinger's exact-multiply path above needs BOTH the significand and 10^|expo|
  to be exactly representable, which caps it at 15 digits and |expo| <= 22.
  Everything past that fell to ExDecNearest, whose every comparison expands a
  candidate double to its EXACT decimal (~765 digits for a subnormal). That is
  correct by construction and priced accordingly — 17 us at expo=23, half a
  millisecond at expo=-300.

  Eisel-Lemire (what CPython, Go, Rust and Abseil use) answers with ONE 128-bit
  multiply against a table of truncated powers of ten. The property that makes
  it safe to bolt in front of an exact parser rather than replace it: it
  DETECTS the cases where the truncated product cannot decide the rounding and
  DECLINES, rather than guessing. So the composition is fast-path, Lemire, then
  ExDecNearest for the residue — and the residue is still correctly rounded by
  construction, because nothing about ExDecNearest changed.

  WHAT IT DECLINES, all of which fall through to ExDecNearest and are therefore
  still exactly right, just not fast:
    * a SUBNORMAL result. This is the reference algorithm's own boundary, not a
      shortcut taken here: below the normal floor there are fewer than 53 bits
      of significand and the truncated 128-bit product no longer carries enough
      to settle the rounding. Declining is the whole reason this can be trusted.
      It also means the two rows this ticket named "small" (1e-310, 1e-320) are
      NOT sped up by this — both are subnormal. Measured, stated, not papered over.
    * overflow to infinity, and any |q| outside the table.
    * more than 19 significant digits (would not fit the u64 significand).
    * the handful of genuinely ambiguous products the two checks below catch.

  The 128-bit multiply itself is MulHiU64 from lib/rtl/wideint.pas — an
  intrinsic (one instruction) on 64-bit targets, a schoolbook fallback on
  32-bit. The low half of a 128-bit product is just the wrapping a*b.

  Table: floor(10^q * 2^k) normalised so the top bit is set, q = -348..347, the
  same range Go's strconv uses. Generated, then checked against a published
  reference entry before it was trusted (q=-348 is FA8FD5A0081C0288 /
  1732C869CD60E453). These are INTEGER literals, so nothing here re-enters the
  float parser this code is part of.

  WHAT THE TABLE COSTS, since it is paid by every binary that links sysutils
  and not only by ones that parse floats: +42 KB of CODE and +11 KB of bss,
  and about +22 us of startup. Only ~11 KB of that is the table's own bytes —
  the other ~31 KB is the compiler emitting a typed const array as
  fill-it-at-startup code rather than as initialised data
  ([[bug-a-a-typed-const-array-is-built-by-startup-code-not-stored-as-data]]).
  Encoding the table as a string blob dodges that and was deliberately NOT
  done: it would hide the compiler bug and make the table unauditable, which
  the platonic-code rule forbids. When that bug is fixed this unit gets ~31 KB
  smaller with no edit here.

  It also costs about 5% on the Clinger fast path above — measured, interleaved
  A/B, and attributable to code layout rather than to any added work on that
  path (adding the same local to the old parser without the table changed
  nothing). That is the trade: ~5% on the common case to take everything
  outside Clinger's window from 18-526 us down to well under 1 us.

  [[bug-b-strtofloat-is-3600x-slower-than-cpython-for-small-exponents]] }

const
  EL_MIN_Q = -348;
  EL_MAX_Q = 347;

  P10Hi: array[0..695] of UInt64 = (
    $FA8FD5A0081C0288, $9C99E58405118195, $C3C05EE50655E1FA, $F4B0769E47EB5A78,
    $98EE4A22ECF3188B, $BF29DCABA82FDEAE, $EEF453D6923BD65A, $9558B4661B6565F8,
    $BAAEE17FA23EBF76, $E95A99DF8ACE6F53, $91D8A02BB6C10594, $B64EC836A47146F9,
    $E3E27A444D8D98B7, $8E6D8C6AB0787F72, $B208EF855C969F4F, $DE8B2B66B3BC4723,
    $8B16FB203055AC76, $ADDCB9E83C6B1793, $D953E8624B85DD78, $87D4713D6F33AA6B,
    $A9C98D8CCB009506, $D43BF0EFFDC0BA48, $84A57695FE98746D, $A5CED43B7E3E9188,
    $CF42894A5DCE35EA, $818995CE7AA0E1B2, $A1EBFB4219491A1F, $CA66FA129F9B60A6,
    $FD00B897478238D0, $9E20735E8CB16382, $C5A890362FDDBC62, $F712B443BBD52B7B,
    $9A6BB0AA55653B2D, $C1069CD4EABE89F8, $F148440A256E2C76, $96CD2A865764DBCA,
    $BC807527ED3E12BC, $EBA09271E88D976B, $93445B8731587EA3, $B8157268FDAE9E4C,
    $E61ACF033D1A45DF, $8FD0C16206306BAB, $B3C4F1BA87BC8696, $E0B62E2929ABA83C,
    $8C71DCD9BA0B4925, $AF8E5410288E1B6F, $DB71E91432B1A24A, $892731AC9FAF056E,
    $AB70FE17C79AC6CA, $D64D3D9DB981787D, $85F0468293F0EB4E, $A76C582338ED2621,
    $D1476E2C07286FAA, $82CCA4DB847945CA, $A37FCE126597973C, $CC5FC196FEFD7D0C,
    $FF77B1FCBEBCDC4F, $9FAACF3DF73609B1, $C795830D75038C1D, $F97AE3D0D2446F25,
    $9BECCE62836AC577, $C2E801FB244576D5, $F3A20279ED56D48A, $9845418C345644D6,
    $BE5691EF416BD60C, $EDEC366B11C6CB8F, $94B3A202EB1C3F39, $B9E08A83A5E34F07,
    $E858AD248F5C22C9, $91376C36D99995BE, $B58547448FFFFB2D, $E2E69915B3FFF9F9,
    $8DD01FAD907FFC3B, $B1442798F49FFB4A, $DD95317F31C7FA1D, $8A7D3EEF7F1CFC52,
    $AD1C8EAB5EE43B66, $D863B256369D4A40, $873E4F75E2224E68, $A90DE3535AAAE202,
    $D3515C2831559A83, $8412D9991ED58091, $A5178FFF668AE0B6, $CE5D73FF402D98E3,
    $80FA687F881C7F8E, $A139029F6A239F72, $C987434744AC874E, $FBE9141915D7A922,
    $9D71AC8FADA6C9B5, $C4CE17B399107C22, $F6019DA07F549B2B, $99C102844F94E0FB,
    $C0314325637A1939, $F03D93EEBC589F88, $96267C7535B763B5, $BBB01B9283253CA2,
    $EA9C227723EE8BCB, $92A1958A7675175F, $B749FAED14125D36, $E51C79A85916F484,
    $8F31CC0937AE58D2, $B2FE3F0B8599EF07, $DFBDCECE67006AC9, $8BD6A141006042BD,
    $AECC49914078536D, $DA7F5BF590966848, $888F99797A5E012D, $AAB37FD7D8F58178,
    $D5605FCDCF32E1D6, $855C3BE0A17FCD26, $A6B34AD8C9DFC06F, $D0601D8EFC57B08B,
    $823C12795DB6CE57, $A2CB1717B52481ED, $CB7DDCDDA26DA268, $FE5D54150B090B02,
    $9EFA548D26E5A6E1, $C6B8E9B0709F109A, $F867241C8CC6D4C0, $9B407691D7FC44F8,
    $C21094364DFB5636, $F294B943E17A2BC4, $979CF3CA6CEC5B5A, $BD8430BD08277231,
    $ECE53CEC4A314EBD, $940F4613AE5ED136, $B913179899F68584, $E757DD7EC07426E5,
    $9096EA6F3848984F, $B4BCA50B065ABE63, $E1EBCE4DC7F16DFB, $8D3360F09CF6E4BD,
    $B080392CC4349DEC, $DCA04777F541C567, $89E42CAAF9491B60, $AC5D37D5B79B6239,
    $D77485CB25823AC7, $86A8D39EF77164BC, $A8530886B54DBDEB, $D267CAA862A12D66,
    $8380DEA93DA4BC60, $A46116538D0DEB78, $CD795BE870516656, $806BD9714632DFF6,
    $A086CFCD97BF97F3, $C8A883C0FDAF7DF0, $FAD2A4B13D1B5D6C, $9CC3A6EEC6311A63,
    $C3F490AA77BD60FC, $F4F1B4D515ACB93B, $991711052D8BF3C5, $BF5CD54678EEF0B6,
    $EF340A98172AACE4, $9580869F0E7AAC0E, $BAE0A846D2195712, $E998D258869FACD7,
    $91FF83775423CC06, $B67F6455292CBF08, $E41F3D6A7377EECA, $8E938662882AF53E,
    $B23867FB2A35B28D, $DEC681F9F4C31F31, $8B3C113C38F9F37E, $AE0B158B4738705E,
    $D98DDAEE19068C76, $87F8A8D4CFA417C9, $A9F6D30A038D1DBC, $D47487CC8470652B,
    $84C8D4DFD2C63F3B, $A5FB0A17C777CF09, $CF79CC9DB955C2CC, $81AC1FE293D599BF,
    $A21727DB38CB002F, $CA9CF1D206FDC03B, $FD442E4688BD304A, $9E4A9CEC15763E2E,
    $C5DD44271AD3CDBA, $F7549530E188C128, $9A94DD3E8CF578B9, $C13A148E3032D6E7,
    $F18899B1BC3F8CA1, $96F5600F15A7B7E5, $BCB2B812DB11A5DE, $EBDF661791D60F56,
    $936B9FCEBB25C995, $B84687C269EF3BFB, $E65829B3046B0AFA, $8FF71A0FE2C2E6DC,
    $B3F4E093DB73A093, $E0F218B8D25088B8, $8C974F7383725573, $AFBD2350644EEACF,
    $DBAC6C247D62A583, $894BC396CE5DA772, $AB9EB47C81F5114F, $D686619BA27255A2,
    $8613FD0145877585, $A798FC4196E952E7, $D17F3B51FCA3A7A0, $82EF85133DE648C4,
    $A3AB66580D5FDAF5, $CC963FEE10B7D1B3, $FFBBCFE994E5C61F, $9FD561F1FD0F9BD3,
    $C7CABA6E7C5382C8, $F9BD690A1B68637B, $9C1661A651213E2D, $C31BFA0FE5698DB8,
    $F3E2F893DEC3F126, $986DDB5C6B3A76B7, $BE89523386091465, $EE2BA6C0678B597F,
    $94DB483840B717EF, $BA121A4650E4DDEB, $E896A0D7E51E1566, $915E2486EF32CD60,
    $B5B5ADA8AAFF80B8, $E3231912D5BF60E6, $8DF5EFABC5979C8F, $B1736B96B6FD83B3,
    $DDD0467C64BCE4A0, $8AA22C0DBEF60EE4, $AD4AB7112EB3929D, $D89D64D57A607744,
    $87625F056C7C4A8B, $A93AF6C6C79B5D2D, $D389B47879823479, $843610CB4BF160CB,
    $A54394FE1EEDB8FE, $CE947A3DA6A9273E, $811CCC668829B887, $A163FF802A3426A8,
    $C9BCFF6034C13052, $FC2C3F3841F17C67, $9D9BA7832936EDC0, $C5029163F384A931,
    $F64335BCF065D37D, $99EA0196163FA42E, $C06481FB9BCF8D39, $F07DA27A82C37088,
    $964E858C91BA2655, $BBE226EFB628AFEA, $EADAB0ABA3B2DBE5, $92C8AE6B464FC96F,
    $B77ADA0617E3BBCB, $E55990879DDCAABD, $8F57FA54C2A9EAB6, $B32DF8E9F3546564,
    $DFF9772470297EBD, $8BFBEA76C619EF36, $AEFAE51477A06B03, $DAB99E59958885C4,
    $88B402F7FD75539B, $AAE103B5FCD2A881, $D59944A37C0752A2, $857FCAE62D8493A5,
    $A6DFBD9FB8E5B88E, $D097AD07A71F26B2, $825ECC24C873782F, $A2F67F2DFA90563B,
    $CBB41EF979346BCA, $FEA126B7D78186BC, $9F24B832E6B0F436, $C6EDE63FA05D3143,
    $F8A95FCF88747D94, $9B69DBE1B548CE7C, $C24452DA229B021B, $F2D56790AB41C2A2,
    $97C560BA6B0919A5, $BDB6B8E905CB600F, $ED246723473E3813, $9436C0760C86E30B,
    $B94470938FA89BCE, $E7958CB87392C2C2, $90BD77F3483BB9B9, $B4ECD5F01A4AA828,
    $E2280B6C20DD5232, $8D590723948A535F, $B0AF48EC79ACE837, $DCDB1B2798182244,
    $8A08F0F8BF0F156B, $AC8B2D36EED2DAC5, $D7ADF884AA879177, $86CCBB52EA94BAEA,
    $A87FEA27A539E9A5, $D29FE4B18E88640E, $83A3EEEEF9153E89, $A48CEAAAB75A8E2B,
    $CDB02555653131B6, $808E17555F3EBF11, $A0B19D2AB70E6ED6, $C8DE047564D20A8B,
    $FB158592BE068D2E, $9CED737BB6C4183D, $C428D05AA4751E4C, $F53304714D9265DF,
    $993FE2C6D07B7FAB, $BF8FDB78849A5F96, $EF73D256A5C0F77C, $95A8637627989AAD,
    $BB127C53B17EC159, $E9D71B689DDE71AF, $9226712162AB070D, $B6B00D69BB55C8D1,
    $E45C10C42A2B3B05, $8EB98A7A9A5B04E3, $B267ED1940F1C61C, $DF01E85F912E37A3,
    $8B61313BBABCE2C6, $AE397D8AA96C1B77, $D9C7DCED53C72255, $881CEA14545C7575,
    $AA242499697392D2, $D4AD2DBFC3D07787, $84EC3C97DA624AB4, $A6274BBDD0FADD61,
    $CFB11EAD453994BA, $81CEB32C4B43FCF4, $A2425FF75E14FC31, $CAD2F7F5359A3B3E,
    $FD87B5F28300CA0D, $9E74D1B791E07E48, $C612062576589DDA, $F79687AED3EEC551,
    $9ABE14CD44753B52, $C16D9A0095928A27, $F1C90080BAF72CB1, $971DA05074DA7BEE,
    $BCE5086492111AEA, $EC1E4A7DB69561A5, $9392EE8E921D5D07, $B877AA3236A4B449,
    $E69594BEC44DE15B, $901D7CF73AB0ACD9, $B424DC35095CD80F, $E12E13424BB40E13,
    $8CBCCC096F5088CB, $AFEBFF0BCB24AAFE, $DBE6FECEBDEDD5BE, $89705F4136B4A597,
    $ABCC77118461CEFC, $D6BF94D5E57A42BC, $8637BD05AF6C69B5, $A7C5AC471B478423,
    $D1B71758E219652B, $83126E978D4FDF3B, $A3D70A3D70A3D70A, $CCCCCCCCCCCCCCCC,
    $8000000000000000, $A000000000000000, $C800000000000000, $FA00000000000000,
    $9C40000000000000, $C350000000000000, $F424000000000000, $9896800000000000,
    $BEBC200000000000, $EE6B280000000000, $9502F90000000000, $BA43B74000000000,
    $E8D4A51000000000, $9184E72A00000000, $B5E620F480000000, $E35FA931A0000000,
    $8E1BC9BF04000000, $B1A2BC2EC5000000, $DE0B6B3A76400000, $8AC7230489E80000,
    $AD78EBC5AC620000, $D8D726B7177A8000, $878678326EAC9000, $A968163F0A57B400,
    $D3C21BCECCEDA100, $84595161401484A0, $A56FA5B99019A5C8, $CECB8F27F4200F3A,
    $813F3978F8940984, $A18F07D736B90BE5, $C9F2C9CD04674EDE, $FC6F7C4045812296,
    $9DC5ADA82B70B59D, $C5371912364CE305, $F684DF56C3E01BC6, $9A130B963A6C115C,
    $C097CE7BC90715B3, $F0BDC21ABB48DB20, $96769950B50D88F4, $BC143FA4E250EB31,
    $EB194F8E1AE525FD, $92EFD1B8D0CF37BE, $B7ABC627050305AD, $E596B7B0C643C719,
    $8F7E32CE7BEA5C6F, $B35DBF821AE4F38B, $E0352F62A19E306E, $8C213D9DA502DE45,
    $AF298D050E4395D6, $DAF3F04651D47B4C, $88D8762BF324CD0F, $AB0E93B6EFEE0053,
    $D5D238A4ABE98068, $85A36366EB71F041, $A70C3C40A64E6C51, $D0CF4B50CFE20765,
    $82818F1281ED449F, $A321F2D7226895C7, $CBEA6F8CEB02BB39, $FEE50B7025C36A08,
    $9F4F2726179A2245, $C722F0EF9D80AAD6, $F8EBAD2B84E0D58B, $9B934C3B330C8577,
    $C2781F49FFCFA6D5, $F316271C7FC3908A, $97EDD871CFDA3A56, $BDE94E8E43D0C8EC,
    $ED63A231D4C4FB27, $945E455F24FB1CF8, $B975D6B6EE39E436, $E7D34C64A9C85D44,
    $90E40FBEEA1D3A4A, $B51D13AEA4A488DD, $E264589A4DCDAB14, $8D7EB76070A08AEC,
    $B0DE65388CC8ADA8, $DD15FE86AFFAD912, $8A2DBF142DFCC7AB, $ACB92ED9397BF996,
    $D7E77A8F87DAF7FB, $86F0AC99B4E8DAFD, $A8ACD7C0222311BC, $D2D80DB02AABD62B,
    $83C7088E1AAB65DB, $A4B8CAB1A1563F52, $CDE6FD5E09ABCF26, $80B05E5AC60B6178,
    $A0DC75F1778E39D6, $C913936DD571C84C, $FB5878494ACE3A5F, $9D174B2DCEC0E47B,
    $C45D1DF942711D9A, $F5746577930D6500, $9968BF6ABBE85F20, $BFC2EF456AE276E8,
    $EFB3AB16C59B14A2, $95D04AEE3B80ECE5, $BB445DA9CA61281F, $EA1575143CF97226,
    $924D692CA61BE758, $B6E0C377CFA2E12E, $E498F455C38B997A, $8EDF98B59A373FEC,
    $B2977EE300C50FE7, $DF3D5E9BC0F653E1, $8B865B215899F46C, $AE67F1E9AEC07187,
    $DA01EE641A708DE9, $884134FE908658B2, $AA51823E34A7EEDE, $D4E5E2CDC1D1EA96,
    $850FADC09923329E, $A6539930BF6BFF45, $CFE87F7CEF46FF16, $81F14FAE158C5F6E,
    $A26DA3999AEF7749, $CB090C8001AB551C, $FDCB4FA002162A63, $9E9F11C4014DDA7E,
    $C646D63501A1511D, $F7D88BC24209A565, $9AE757596946075F, $C1A12D2FC3978937,
    $F209787BB47D6B84, $9745EB4D50CE6332, $BD176620A501FBFF, $EC5D3FA8CE427AFF,
    $93BA47C980E98CDF, $B8A8D9BBE123F017, $E6D3102AD96CEC1D, $9043EA1AC7E41392,
    $B454E4A179DD1877, $E16A1DC9D8545E94, $8CE2529E2734BB1D, $B01AE745B101E9E4,
    $DC21A1171D42645D, $899504AE72497EBA, $ABFA45DA0EDBDE69, $D6F8D7509292D603,
    $865B86925B9BC5C2, $A7F26836F282B732, $D1EF0244AF2364FF, $8335616AED761F1F,
    $A402B9C5A8D3A6E7, $CD036837130890A1, $802221226BE55A64, $A02AA96B06DEB0FD,
    $C83553C5C8965D3D, $FA42A8B73ABBF48C, $9C69A97284B578D7, $C38413CF25E2D70D,
    $F46518C2EF5B8CD1, $98BF2F79D5993802, $BEEEFB584AFF8603, $EEAABA2E5DBF6784,
    $952AB45CFA97A0B2, $BA756174393D88DF, $E912B9D1478CEB17, $91ABB422CCB812EE,
    $B616A12B7FE617AA, $E39C49765FDF9D94, $8E41ADE9FBEBC27D, $B1D219647AE6B31C,
    $DE469FBD99A05FE3, $8AEC23D680043BEE, $ADA72CCC20054AE9, $D910F7FF28069DA4,
    $87AA9AFF79042286, $A99541BF57452B28, $D3FA922F2D1675F2, $847C9B5D7C2E09B7,
    $A59BC234DB398C25, $CF02B2C21207EF2E, $8161AFB94B44F57D, $A1BA1BA79E1632DC,
    $CA28A291859BBF93, $FCB2CB35E702AF78, $9DEFBF01B061ADAB, $C56BAEC21C7A1916,
    $F6C69A72A3989F5B, $9A3C2087A63F6399, $C0CB28A98FCF3C7F, $F0FDF2D3F3C30B9F,
    $969EB7C47859E743, $BC4665B596706114, $EB57FF22FC0C7959, $9316FF75DD87CBD8,
    $B7DCBF5354E9BECE, $E5D3EF282A242E81, $8FA475791A569D10, $B38D92D760EC4455,
    $E070F78D3927556A, $8C469AB843B89562, $AF58416654A6BABB, $DB2E51BFE9D0696A,
    $88FCF317F22241E2, $AB3C2FDDEEAAD25A, $D60B3BD56A5586F1, $85C7056562757456,
    $A738C6BEBB12D16C, $D106F86E69D785C7, $82A45B450226B39C, $A34D721642B06084,
    $CC20CE9BD35C78A5, $FF290242C83396CE, $9F79A169BD203E41, $C75809C42C684DD1,
    $F92E0C3537826145, $9BBCC7A142B17CCB, $C2ABF989935DDBFE, $F356F7EBF83552FE,
    $98165AF37B2153DE, $BE1BF1B059E9A8D6, $EDA2EE1C7064130C, $9485D4D1C63E8BE7,
    $B9A74A0637CE2EE1, $E8111C87C5C1BA99, $910AB1D4DB9914A0, $B54D5E4A127F59C8,
    $E2A0B5DC971F303A, $8DA471A9DE737E24, $B10D8E1456105DAD, $DD50F1996B947518,
    $8A5296FFE33CC92F, $ACE73CBFDC0BFB7B, $D8210BEFD30EFA5A, $8714A775E3E95C78,
    $A8D9D1535CE3B396, $D31045A8341CA07C, $83EA2B892091E44D, $A4E4B66B68B65D60,
    $CE1DE40642E3F4B9, $80D2AE83E9CE78F3, $A1075A24E4421730, $C94930AE1D529CFC,
    $FB9B7CD9A4A7443C, $9D412E0806E88AA5, $C491798A08A2AD4E, $F5B5D7EC8ACB58A2,
    $9991A6F3D6BF1765, $BFF610B0CC6EDD3F, $EFF394DCFF8A948E, $95F83D0A1FB69CD9,
    $BB764C4CA7A4440F, $EA53DF5FD18D5513, $92746B9BE2F8552C, $B7118682DBB66A77,
    $E4D5E82392A40515, $8F05B1163BA6832D, $B2C71D5BCA9023F8, $DF78E4B2BD342CF6,
    $8BAB8EEFB6409C1A, $AE9672ABA3D0C320, $DA3C0F568CC4F3E8, $8865899617FB1871,
    $AA7EEBFB9DF9DE8D, $D51EA6FA85785631, $8533285C936B35DE, $A67FF273B8460356,
    $D01FEF10A657842C, $8213F56A67F6B29B, $A298F2C501F45F42, $CB3F2F7642717713,
    $FE0EFB53D30DD4D7, $9EC95D1463E8A506, $C67BB4597CE2CE48, $F81AA16FDC1B81DA,
    $9B10A4E5E9913128, $C1D4CE1F63F57D72, $F24A01A73CF2DCCF, $976E41088617CA01,
    $BD49D14AA79DBC82, $EC9C459D51852BA2, $93E1AB8252F33B45, $B8DA1662E7B00A17,
    $E7109BFBA19C0C9D, $906A617D450187E2, $B484F9DC9641E9DA, $E1A63853BBD26451,
    $8D07E33455637EB2, $B049DC016ABC5E5F, $DC5C5301C56B75F7, $89B9B3E11B6329BA,
    $AC2820D9623BF429, $D732290FBACAF133, $867F59A9D4BED6C0, $A81F301449EE8C70,
    $D226FC195C6A2F8C, $83585D8FD9C25DB7, $A42E74F3D032F525, $CD3A1230C43FB26F,
    $80444B5E7AA7CF85, $A0555E361951C366, $C86AB5C39FA63440, $FA856334878FC150,
    $9C935E00D4B9D8D2, $C3B8358109E84F07, $F4A642E14C6262C8, $98E7E9CCCFBD7DBD,
    $BF21E44003ACDD2C, $EEEA5D5004981478, $95527A5202DF0CCB, $BAA718E68396CFFD,
    $E950DF20247C83FD, $91D28B7416CDD27E, $B6472E511C81471D, $E3D8F9E563A198E5,
    $8E679C2F5E44FF8F, $B201833B35D63F73, $DE81E40A034BCF4F, $8B112E86420F6191,
    $ADD57A27D29339F6, $D94AD8B1C7380874, $87CEC76F1C830548, $A9C2794AE3A3C69A,
    $D433179D9C8CB841, $849FEEC281D7F328, $A5C7EA73224DEFF3, $CF39E50FEAE16BEF,
    $81842F29F2CCE375, $A1E53AF46F801C53, $CA5E89B18B602368, $FCF62C1DEE382C42,
    $9E19DB92B4E31BA9, $C5A05277621BE293, $F70867153AA2DB38, $9A65406D44A5C903,
    $C0FE908895CF3B44, $F13E34AABB430A15, $96C6E0EAB509E64D, $BC789925624C5FE0,
    $EB96BF6EBADF77D8, $933E37A534CBAAE7, $B80DC58E81FE95A1, $E61136F2227E3B09,
    $8FCAC257558EE4E6, $B3BD72ED2AF29E1F, $E0ACCFA875AF45A7, $8C6C01C9498D8B88,
    $AF87023B9BF0EE6A, $DB68C2CA82ED2A05, $892179BE91D43A43, $AB69D82E364948D4,
    $D6444E39C3DB9B09, $85EAB0E41A6940E5, $A7655D1D2103911F, $D13EB46469447567);

  P10Lo: array[0..695] of UInt64 = (
    $1732C869CD60E453, $0E7FBD42205C8EB4, $521FAC92A873B261, $E6A797B752909EF9,
    $9028BED2939A635C, $7432EE873880FC33, $113FAA2906A13B3F, $4AC7CA59A424C507,
    $5D79BCF00D2DF649, $F4D82C2C107973DC, $79071B9B8A4BE869, $9748E2826CDEE284,
    $FD1B1B2308169B25, $FE30F0F5E50E20F7, $BDBD2D335E51A935, $AD2C788035E61382,
    $4C3BCB5021AFCC31, $DF4ABE242A1BBF3D, $D71D6DAD34A2AF0D, $8672648C40E5AD68,
    $680EFDAF511F18C2, $0212BD1B2566DEF2, $014BB630F7604B57, $419EA3BD35385E2D,
    $52064CAC828675B9, $7343EFEBD1940993, $1014EBE6C5F90BF8, $D41A26E077774EF6,
    $8920B098955522B4, $55B46E5F5D5535B0, $EB2189F734AA831D, $A5E9EC7501D523E4,
    $47B233C92125366E, $999EC0BB696E840A, $C00670EA43CA250D, $380406926A5E5728,
    $C605083704F5ECF2, $F7864A44C633682E, $7AB3EE6AFBE0211D, $5960EA05BAD82964,
    $6FB92487298E33BD, $A5D3B6D479F8E056, $8F48A4899877186C, $331ACDABFE94DE87,
    $9FF0C08B7F1D0B14, $07ECF0AE5EE44DD9, $C9E82CD9F69D6150, $BE311C083A225CD2,
    $6DBD630A48AAF406, $092CBBCCDAD5B108, $25BBF56008C58EA5, $AF2AF2B80AF6F24E,
    $1AF5AF660DB4AEE1, $50D98D9FC890ED4D, $E50FF107BAB528A0, $1E53ED49A96272C8,
    $25E8E89C13BB0F7A, $77B191618C54E9AC, $D59DF5B9EF6A2417, $4B0573286B44AD1D,
    $4EE367F9430AEC32, $229C41F793CDA73F, $6B43527578C1110F, $830A13896B78AAA9,
    $23CC986BC656D553, $2CBFBE86B7EC8AA8, $7BF7D71432F3D6A9, $DAF5CCD93FB0CC53,
    $D1B3400F8F9CFF68, $23100809B9C21FA1, $ABD40A0C2832A78A, $16C90C8F323F516C,
    $AE3DA7D97F6792E3, $99CD11CFDF41779C, $40405643D711D583, $482835EA666B2572,
    $DA3243650005EECF, $90BED43E40076A82, $5A7744A6E804A291, $711515D0A205CB36,
    $0D5A5B44CA873E03, $E858790AFE9486C2, $626E974DBE39A872, $FB0A3D212DC8128F,
    $7CE66634BC9D0B99, $1C1FFFC1EBC44E80, $A327FFB266B56220, $4BF1FF9F0062BAA8,
    $6F773FC3603DB4A9, $CB550FB4384D21D3, $7E2A53A146606A48, $2EDA7444CBFC426D,
    $FA911155FEFB5308, $793555AB7EBA27CA, $4BC1558B2F3458DE, $9EB1AAEDFB016F16,
    $465E15A979C1CADC, $0BFACD89EC191EC9, $CEF980EC671F667B, $82B7E12780E7401A,
    $D1B2ECB8B0908810, $861FA7E6DCB4AA15, $67A791E093E1D49A, $E0C8BB2C5C6D24E0,
    $58FAE9F773886E18, $AF39A475506A899E, $6D8406C952429603, $C8E5087BA6D33B83,
    $FB1E4A9A90880A64, $5CF2EEA09A55067F, $F42FAA48C0EA481E, $F13B94DAF124DA26,
    $76C53D08D6B70858, $54768C4B0C64CA6E, $A9942F5DCF7DFD09, $D3F93B35435D7C4C,
    $C47BC5014A1A6DAF, $359AB6419CA1091B, $C30163D203C94B62, $79E0DE63425DCF1D,
    $985915FC12F542E4, $3E6F5B7B17B2939D, $A705992CEECF9C42, $50C6FF782A838353,
    $A4F8BF5635246428, $871B7795E136BE99, $28E2557B59846E3F, $331AEADA2FE589CF,
    $3FF0D2C85DEF7621, $0FED077A756B53A9, $D3E8495912C62894, $64712DD7ABBBD95C,
    $BD8D794D96AACFB3, $ECF0D7A0FC5583A0, $F41686C49DB57244, $311C2875C522CED5,
    $7D633293366B828B, $AE5DFF9C02033197, $D9F57F830283FDFC, $D072DF63C324FD7B,
    $4247CB9E59F71E6D, $52D9BE85F074E608, $67902E276C921F8B, $00BA1CD8A3DB53B6,
    $80E8A40ECCD228A4, $6122CD128006B2CD, $796B805720085F81, $CBE3303674053BB0,
    $BEDBFC4411068A9C, $EE92FB5515482D44, $751BDD152D4D1C4A, $D262D45A78A0635D,
    $86FB897116C87C34, $D45D35E6AE3D4DA0, $8974836059CCA109, $2BD1A438703FC94B,
    $7B6306A34627DDCF, $1A3BC84C17B1D542, $20CABA5F1D9E4A93, $547EB47B7282EE9C,
    $E99E619A4F23AA43, $6405FA00E2EC94D4, $DE83BC408DD3DD04, $9624AB50B148D445,
    $3BADD624DD9B0957, $E54CA5D70A80E5D6, $5E9FCF4CCD211F4C, $7647C3200069671F,
    $29ECD9F40041E073, $F468107100525890, $7182148D4066EEB4, $C6F14CD848405530,
    $B8ADA00E5A506A7C, $A6D90811F0E4851C, $908F4A166D1DA663, $9A598E4E043287FE,
    $40EFF1E1853F29FD, $D12BEE59E68EF47C, $82BB74F8301958CE, $E36A52363C1FAF01,
    $DC44E6C3CB279AC1, $29AB103A5EF8C0B9, $7415D448F6B6F0E7, $111B495B3464AD21,
    $CAB10DD900BEEC34, $3D5D514F40EEA742, $0CB4A5A3112A5112, $47F0E785EABA72AB,
    $59ED216765690F56, $306869C13EC3532C, $1E414218C73A13FB, $E5D1929EF90898FA,
    $DF45F746B74ABF39, $6B8BBA8C328EB783, $066EA92F3F326564, $C80A537B0EFEFEBD,
    $BD06742CE95F5F36, $2C48113823B73704, $F75A15862CA504C5, $9A984D73DBE722FB,
    $C13E60D0D2E0EBBA, $318DF905079926A8, $FDF17746497F7052, $FEB6EA8BEDEFA633,
    $FE64A52EE96B8FC0, $3DFDCE7AA3C673B0, $06BEA10CA65C084E, $486E494FCFF30A62,
    $5A89DBA3C3EFCCFA, $F89629465A75E01C, $F6BBB397F1135823, $746AA07DED582E2C,
    $A8C2A44EB4571CDC, $92F34D62616CE413, $77B020BAF9C81D17, $0ACE1474DC1D122E,
    $0D819992132456BA, $10E1FFF697ED6C69, $CA8D3FFA1EF463C1, $BD308FF8A6B17CB2,
    $AC7CB3F6D05DDBDE, $6BCDF07A423AA96B, $86C16C98D2C953C6, $E871C7BF077BA8B7,
    $11471CD764AD4972, $D598E40D3DD89BCF, $4AFF1D108D4EC2C3, $CEDF722A585139BA,
    $C2974EB4EE658828, $733D226229FEEA32, $0806357D5A3F525F, $CA07C2DCB0CF26F7,
    $FC89B393DD02F0B5, $BBAC2078D443ACE2, $D54B944B84AA4C0D, $0A9E795E65D4DF11,
    $4D4617B5FF4A16D5, $504BCED1BF8E4E45, $E45EC2862F71E1D6, $5D767327BB4E5A4C,
    $3A6A07F8D510F86F, $890489F70A55368B, $2B45AC74CCEA842E, $3B0B8BC90012929D,
    $09CE6EBB40173744, $CC420A6A101D0515, $9FA946824A12232D, $47939822DC96ABF9,
    $59787E2B93BC56F7, $57EB4EDB3C55B65A, $EDE622920B6B23F1, $E95FAB368E45ECED,
    $11DBCB0218EBB414, $D652BDC29F26A119, $4BE76D3346F0495F, $6F70A4400C562DDB,
    $CB4CCD500F6BB952, $7E2000A41346A7A7, $8ED400668C0C28C8, $728900802F0F32FA,
    $4F2B40A03AD2FFB9, $E2F610C84987BFA8, $0DD9CA7D2DF4D7C9, $91503D1C79720DBB,
    $75A44C6397CE912A, $C986AFBE3EE11ABA, $FBE85BADCE996168, $FAE27299423FB9C3,
    $DCCD879FC967D41A, $5400E987BBC1C920, $290123E9AAB23B68, $F9A0B6720AAF6521,
    $F808E40E8D5B3E69, $B60B1D1230B20E04, $B1C6F22B5E6F48C2, $1E38AEB6360B1AF3,
    $25C6DA63C38DE1B0, $579C487E5A38AD0E, $2D835A9DF0C6D851, $F8E431456CF88E65,
    $1B8E9ECB641B58FF, $E272467E3D222F3F, $5B0ED81DCC6ABB0F, $98E947129FC2B4E9,
    $3F2398D747B36224, $8EEC7F0D19A03AAD, $1953CF68300424AC, $5FA8C3423C052DD7,
    $3792F412CB06794D, $E2BBD88BBEE40BD0, $5B6ACEAEAE9D0EC4, $F245825A5A445275,
    $EED6E2F0F0D56712, $55464DD69685606B, $AA97E14C3C26B886, $D53DD99F4B3066A8,
    $E546A8038EFE4029, $DE98520472BDD033, $963E66858F6D4440, $DDE7001379A44AA8,
    $5560C018580D5D52, $AAB8F01E6E10B4A6, $CAB3961304CA70E8, $3D607B97C5FD0D22,
    $8CB89A7DB77C506A, $77F3608E92ADB242, $55F038B237591ED3, $6B6C46DEC52F6688,
    $2323AC4B3B3DA015, $ABEC975E0A0D081A, $96E7BD358C904A21, $7E50D64177DA2E54,
    $DDE50BD1D5D0B9E9, $955E4EC64B44E864, $BD5AF13BEF0B113E, $ECB1AD8AEACDD58E,
    $67DE18EDA5814AF2, $80EACF948770CED7, $A1258379A94D028D, $096EE45813A04330,
    $8BCA9D6E188853FC, $775EA264CF55347D, $95364AFE032A819D, $3A83DDBD83F52204,
    $C4926A9672793542, $75B7053C0F178293, $5324C68B12DD6338, $D3F6FC16EBCA5E03,
    $88F4BB1CA6BCF584, $2B31E9E3D06C32E5, $3AFF322E62439FCF, $09BEFEB9FAD487C2,
    $4C2EBE687989A9B3, $0F9D37014BF60A10, $538484C19EF38C94, $2865A5F206B06FB9,
    $F93F87B7442E45D3, $F78F69A51539D748, $B573440E5A884D1B, $31680A88F8953030,
    $FDC20D2B36BA7C3D, $3D32907604691B4C, $A63F9A49C2C1B10F, $0FCF80DC33721D53,
    $D3C36113404EA4A8, $645A1CAC083126E9, $3D70A3D70A3D70A3, $CCCCCCCCCCCCCCCC,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $4000000000000000, $5000000000000000, $A400000000000000, $4D00000000000000,
    $F020000000000000, $6C28000000000000, $C732000000000000, $3C7F400000000000,
    $4B9F100000000000, $1E86D40000000000, $1314448000000000, $17D955A000000000,
    $5DCFAB0800000000, $5AA1CAE500000000, $F14A3D9E40000000, $6D9CCD05D0000000,
    $E4820023A2000000, $DDA2802C8A800000, $D50B2037AD200000, $4526F422CC340000,
    $9670B12B7F410000, $3C0CDD765F114000, $A5880A69FB6AC800, $8EEA0D047A457A00,
    $72A4904598D6D880, $47A6DA2B7F864750, $999090B65F67D924, $FFF4B4E3F741CF6D,
    $BFF8F10E7A8921A4, $AFF72D52192B6A0D, $9BF4F8A69F764490, $02F236D04753D5B4,
    $01D762422C946590, $424D3AD2B7B97EF5, $D2E0898765A7DEB2, $63CC55F49F88EB2F,
    $3CBF6B71C76B25FB, $8BEF464E3945EF7A, $97758BF0E3CBB5AC, $3D52EEED1CBEA317,
    $4CA7AAA863EE4BDD, $8FE8CAA93E74EF6A, $B3E2FD538E122B44, $60DBBCA87196B616,
    $BC8955E946FE31CD, $6BABAB6398BDBE41, $C696963C7EED2DD1, $FC1E1DE5CF543CA2,
    $3B25A55F43294BCB, $49EF0EB713F39EBE, $6E3569326C784337, $49C2C37F07965404,
    $DC33745EC97BE906, $69A028BB3DED71A3, $C40832EA0D68CE0C, $F50A3FA490C30190,
    $792667C6DA79E0FA, $577001B891185938, $ED4C0226B55E6F86, $544F8158315B05B4,
    $696361AE3DB1C721, $03BC3A19CD1E38E9, $04AB48A04065C723, $62EB0D64283F9C76,
    $3BA5D0BD324F8394, $CA8F44EC7EE36479, $7E998B13CF4E1ECB, $9E3FEDD8C321A67E,
    $C5CFE94EF3EA101E, $BBA1F1D158724A12, $2A8A6E45AE8EDC97, $F52D09D71A3293BD,
    $593C2626705F9C56, $6F8B2FB00C77836C, $0B6DFB9C0F956447, $4724BD4189BD5EAC,
    $58EDEC91EC2CB657, $2F2967B66737E3ED, $BD79E0D20082EE74, $ECD8590680A3AA11,
    $E80E6F4820CC9495, $3109058D147FDCDD, $BD4B46F0599FD415, $6C9E18AC7007C91A,
    $03E2CF6BC604DDB0, $84DB8346B786151C, $E612641865679A63, $4FCB7E8F3F60C07E,
    $E3BE5E330F38F09D, $5CADF5BFD3072CC5, $73D9732FC7C8F7F6, $2867E7FDDCDD9AFA,
    $B281E1FD541501B8, $1F225A7CA91A4226, $3375788DE9B06958, $0052D6B1641C83AE,
    $C0678C5DBD23A49A, $F840B7BA963646E0, $B650E5A93BC3D898, $A3E51F138AB4CEBE,
    $C66F336C36B10137, $B80B0047445D4184, $A60DC059157491E5, $87C89837AD68DB2F,
    $29BABE4598C311FB, $F4296DD6FEF3D67A, $1899E4A65F58660C, $5EC05DCFF72E7F8F,
    $76707543F4FA1F73, $6A06494A791C53A8, $0487DB9D17636892, $45A9D2845D3C42B6,
    $0B8A2392BA45A9B2, $8E6CAC7768D7141E, $3207D795430CD926, $7F44E6BD49E807B8,
    $5F16206C9C6209A6, $36DBA887C37A8C0F, $C2494954DA2C9789, $F2DB9BAA10B7BD6C,
    $6F92829494E5ACC7, $CB772339BA1F17F9, $FF2A760414536EFB, $FEF5138519684ABA,
    $7EB258665FC25D69, $EF2F773FFBD97A61, $AAFB550FFACFD8FA, $95BA2A53F983CF38,
    $DD945A747BF26183, $94F971119AEEF9E4, $7A37CD5601AAB85D, $AC62E055C10AB33A,
    $577B986B314D6009, $ED5A7E85FDA0B80B, $14588F13BE847307, $596EB2D8AE258FC8,
    $6FCA5F8ED9AEF3BB, $25DE7BB9480D5854, $AF561AA79A10AE6A, $1B2BA1518094DA04,
    $90FB44D2F05D0842, $353A1607AC744A53, $42889B8997915CE8, $69956135FEBADA11,
    $43FAB9837E699095, $94F967E45E03F4BB, $1D1BE0EEBAC278F5, $6462D92A69731732,
    $7D7B8F7503CFDCFE, $5CDA735244C3D43E, $3A0888136AFA64A7, $088AAA1845B8FDD0,
    $8AAD549E57273D45, $36AC54E2F678864B, $84576A1BB416A7DD, $656D44A2A11C51D5,
    $9F644AE5A4B1B325, $873D5D9F0DDE1FEE, $A90CB506D155A7EA, $09A7F12442D588F2,
    $0C11ED6D538AEB2F, $8F1668C8A86DA5FA, $F96E017D694487BC, $37C981DCC395A9AC,
    $85BBE253F47B1417, $93956D7478CCEC8E, $387AC8D1970027B2, $06997B05FCC0319E,
    $441FECE3BDF81F03, $D527E81CAD7626C3, $8A71E223D8D3B074, $F6872D5667844E49,
    $B428F8AC016561DB, $E13336D701BEBA52, $ECC0024661173473, $27F002D7F95D0190,
    $31EC038DF7B441F4, $7E67047175A15271, $0F0062C6E984D386, $52C07B78A3E60868,
    $A7709A56CCDF8A82, $88A66076400BB691, $6ACFF893D00EA435, $0583F6B8C4124D43,
    $C3727A337A8B704A, $744F18C0592E4C5C, $1162DEF06F79DF73, $8ADDCB5645AC2BA8,
    $6D953E2BD7173692, $C8FA8DB6CCDD0437, $1D9C9892400A22A2, $2503BEB6D00CAB4B,
    $2E44AE64840FD61D, $5CEAECFED289E5D2, $7425A83E872C5F47, $D12F124E28F77719,
    $82BD6B70D99AAA6F, $636CC64D1001550B, $3C47F7E05401AA4E, $65ACFAEC34810A71,
    $7F1839A741A14D0D, $1EDE48111209A050, $934AED0AAB460432, $F81DA84D5617853F,
    $36251260AB9D668E, $C1D72B7C6B426019, $B24CF65B8612F81F, $DEE033F26797B627,
    $169840EF017DA3B1, $8E1F289560EE864E, $F1A6F2BAB92A27E2, $AE10AF696774B1DB,
    $ACCA6DA1E0A8EF29, $17FD090A58D32AF3, $DDFC4B4CEF07F5B0, $4ABDAF101564F98E,
    $9D6D1AD41ABE37F1, $84C86189216DC5ED, $32FD3CF5B4E49BB4, $3FBC8C33221DC2A1,
    $0FABAF3FEAA5334A, $29CB4D87F2A7400E, $743E20E9EF511012, $914DA9246B255416,
    $1AD089B6C2F7548E, $A184AC2473B529B1, $C9E5D72D90A2741E, $7E2FA67C7A658892,
    $DDBB901B98FEEAB7, $552A74227F3EA565, $D53A88958F87275F, $8A892ABAF368F137,
    $2D2B7569B0432D85, $9C3B29620E29FC73, $8349F3BA91B47B8F, $241C70A936219A73,
    $ED238CD383AA0110, $F4363804324A40AA, $B143C6053EDCD0D5, $DD94B7868E94050A,
    $CA7CF2B4191C8326, $FD1C2F611F63A3F0, $BC633B39673C8CEC, $D5BE0503E085D813,
    $4B2D8644D8A74E18, $DDF8E7D60ED1219E, $CABB90E5C942B503, $3D6A751F3B936243,
    $0CC512670A783AD4, $27FB2B80668B24C5, $B1F9F660802DEDF6, $5E7873F8A0396973,
    $DB0B487B6423E1E8, $91CE1A9A3D2CDA62, $7641A140CC7810FB, $A9E904C87FCB0A9D,
    $546345FA9FBDCD44, $A97C177947AD4095, $49ED8EABCCCC485D, $5C68F256BFFF5A74,
    $73832EEC6FFF3111, $C831FD53C5FF7EAB, $BA3E7CA8B77F5E55, $28CE1BD2E55F35EB,
    $7980D163CF5B81B3, $D7E105BCC332621F, $8DD9472BF3FEFAA7, $B14F98F6F0FEB951,
    $6ED1BF9A569F33D3, $0A862F80EC4700C8, $CD27BB612758C0FA, $8038D51CB897789C,
    $E0470A63E6BD56C3, $1858CCFCE06CAC74, $0F37801E0C43EBC8, $D30560258F54E6BA,
    $47C6B82EF32A2069, $4CDC331D57FA5441, $E0133FE4ADF8E952, $58180FDDD97723A6,
    $570F09EAA7EA7648, $2CD2CC6551E513DA, $F8077F7EA65E58D1, $FB04AFAF27FAF782,
    $79C5DB9AF1F9B563, $18375281AE7822BC, $8F2293910D0B15B5, $B2EB3875504DDB22,
    $5FA60692A46151EB, $DBC7C41BA6BCD333, $12B9B522906C0800, $D768226B34870A00,
    $E6A1158300D46640, $60495AE3C1097FD0, $385BB19CB14BDFC4, $46729E03DD9ED7B5,
    $6C07A2C26A8346D1, $C7098B7305241885, $B8CBEE4FC66D1EA7, $737F74F1DC043328,
    $505F522E53053FF2, $647726B9E7C68FEF, $5ECA783430DC19F5, $B67D16413D132072,
    $E41C5BD18C57E88F, $8E91B962F7B6F159, $723627BBB5A4ADB0, $CEC3B1AAA30DD91C,
    $213A4F0AA5E8A7B1, $A988E2CD4F62D19D, $93EB1B80A33B8605, $BC72F130660533C3,
    $EB8FAD7C7F8680B4, $A67398DB9F6820E1, $88083F8943A1148C, $6A0A4F6B948959B0,
    $848CE34679ABB01C, $F2D80E0C0C0B4E11, $6F8E118F0F0E2195, $4B7195F2D2D1A9FB);


{ Leading zeros of a NONZERO UInt64. Called once per parse, so a shift loop is
  cheaper than reaching for an intrinsic that not every target has. }
function EL_Clz(x: UInt64): Integer;
var n: Integer;
begin
  n := 0;
  while (x shr 63) = 0 do
  begin
    x := x shl 1;
    n := n + 1;
  end;
  EL_Clz := n;
end;

{ floor(x / 65536) — FLOOR, not truncation, because x is negative for every
  negative exponent and `div` rounds toward zero. Go writes this as an
  arithmetic `>> 16`; spelled out here so the negative half cannot silently
  become truncation and shift the estimate by one. }
function EL_Floor64K(x: Int64): Int64;
begin
  if x >= 0 then EL_Floor64K := x div 65536
  else EL_Floor64K := -(((-x) + 65535) div 65536);
end;

{ mant * 10^q as a correctly rounded Double, or False if it cannot be decided.
  `mant` is the EXACT decimal significand (no truncation) and q the power of
  ten it is multiplied by. False means "ask ExDecNearest", never "wrong". }
function EiselLemire(mant: UInt64; q: Integer; var value: Double): Boolean;
var
  clz, idx, msb: Integer;
  retExp2: Int64;
  xHi, xLo, yHi, yLo, mHi, mLo, retMant: UInt64;
  bits: Int64;
begin
  EiselLemire := False;
  if mant = 0 then Exit;                        { the caller handles zero }
  if (q < EL_MIN_Q) or (q > EL_MAX_Q) then Exit;

  clz := EL_Clz(mant);
  mant := mant shl clz;
  { 217706/65536 is log2(10) to well within the slack this estimate has; the
    +64 is the table's normalisation and +1023 the IEEE bias. }
  retExp2 := EL_Floor64K(217706 * Int64(q)) + 64 + 1023 - clz;

  idx := q - EL_MIN_Q;
  xHi := MulHiU64(mant, P10Hi[idx]);
  { the low half of a 128-bit product IS the wrapping 64-bit product }
  xLo := mant * P10Hi[idx];

  { The truncated table entry may not settle the rounding on its own. When the
    product sits within 2^-9 of a boundary, bring in the table's LOW word and
    redo the comparison at 128 bits of the multiplier. If it is STILL
    undecidable, decline. `a + b < b` is the unsigned overflow test. }
  if ((xHi and $1FF) = $1FF) and ((xLo + mant) < mant) then
  begin
    yHi := MulHiU64(mant, P10Lo[idx]);
    yLo := mant * P10Lo[idx];
    mHi := xHi;
    mLo := xLo + yHi;
    if mLo < xLo then mHi := mHi + 1;
    if ((mHi and $1FF) = $1FF) and ((mLo + 1) = 0) and ((yLo + mant) < mant) then
      Exit;
    xHi := mHi;
    xLo := mLo;
  end;

  msb := Integer(xHi shr 63);
  retMant := xHi shr (msb + 9);
  retExp2 := retExp2 - Int64(1 - msb);

  { An exact halfway product would round to even, and a truncated product
    cannot prove it is exactly halfway — so this shape is declined too. }
  if (xLo = 0) and ((xHi and $1FF) = 0) and ((retMant and 3) = 1) then Exit;

  retMant := retMant + (retMant and 1);
  retMant := retMant shr 1;
  if (retMant shr 53) > 0 then
  begin
    retMant := retMant shr 1;
    retExp2 := retExp2 + 1;
  end;

  { retExp2 < 1 is subnormal-or-zero, > 2046 is infinity. Both DECLINE — see
    the header. This is the check that keeps the algorithm honest. }
  if (retExp2 < 1) or (retExp2 > 2046) then Exit;

  bits := (retExp2 shl 52) or Int64(retMant and $000FFFFFFFFFFFFF);
  value := ExDecBitsToDouble(bits);
  EiselLemire := True;
end;

function ParseFloatCore(const s: AnsiString; var value: Double): Boolean;
const
  { every digit past this is beyond any midpoint's ~1080, so it can only break
    a tie — which the sticky digit below does, without unbounded strings }
  EXDEC_INMAX = 1200;
var i, digit, e, k: Integer; c: Char; neg, eneg: Boolean;
    w, p: Double; in_frac, started, estarted, sticky: Boolean;
    ds, t: AnsiString; fracCount, nd, expo, lead: Integer; sig: Int64;
    dsLen, dsCap: Integer;
    msig: UInt64;

  { Append one digit to ds without reallocating per digit. The old code was
    `ds := ds + c` inside the scan loop, which reallocates and recopies the
    whole accumulated prefix on EVERY digit -- the same quadratic-append shape
    already fixed once in ExDecOfMant, sitting in a second place. Capacity
    doubles, so an ordinary number costs one allocation and a 1200-digit one
    costs six. }
  procedure DsPush(ch: Char);
  begin
    if dsLen = dsCap then
    begin
      { 32 covers all ordinary input in one allocation; a nested
        procedure cannot see the enclosing const block, hence the literal }
      if dsCap = 0 then dsCap := 32 else dsCap := dsCap * 2;
      SetLength(ds, dsCap);
    end;
    dsLen := dsLen + 1;
    ds[dsLen] := ch;
  end;

begin
  Result := False;
  value := 0.0;
  dsLen := 0; dsCap := 0;
  { FPC skips whitespace at BOTH ends before parsing, and its notion of
    whitespace is any char <= ' ' — measured, not assumed: #0, #1, #11 and #12
    around a float are all accepted there, which is exactly Trim's rule. This
    skipped leading SPACES only, so StrToFloat('1.5 ') and StrToFloat(#9'1.5')
    were rejected and returned the default.
    ([[bug-b-strtofloat-returns-0-for-malformed-input-and-rejects-trailing-space]]) }
  t := Trim(s);
  i := 1; neg := False; w := 0.0; in_frac := False; started := False;
  ds := ''; fracCount := 0; sticky := False;
  if (i <= Length(t)) and ((t[i] = '-') or (t[i] = '+')) then
  begin
    if t[i] = '-' then neg := True;
    i := i + 1;
  end;
  e := 0; eneg := False; estarted := True;
  while i <= Length(t) do
  begin
    c := t[i];
    if (c >= '0') and (c <= '9') then
    begin
      digit := Ord(c) - Ord('0');
      if in_frac then fracCount := fracCount + 1;
      { keep the digits themselves; the value is reconstructed exactly below }
      if dsLen < EXDEC_INMAX then
      begin
        if (dsLen > 0) or (digit <> 0) then DsPush(c);     { drop leading zeros }
      end
      else if digit <> 0 then
        sticky := True;
      started := True;
      i := i + 1;
    end
    else if (c = '.') and (not in_frac) then
    begin
      in_frac := True;
      i := i + 1;
    end
    else if ((c = 'e') or (c = 'E')) and started then
    begin
      { exponent: [+|-]digits to the END of the string ('1e0', '1.2E+003') }
      i := i + 1;
      if (i <= Length(t)) and ((t[i] = '-') or (t[i] = '+')) then
      begin
        if t[i] = '-' then eneg := True;
        i := i + 1;
      end;
      estarted := False;
      while i <= Length(t) do
      begin
        c := t[i];
        if (c < '0') or (c > '9') then Exit;
        e := e * 10 + (Ord(c) - Ord('0'));
        estarted := True;
        i := i + 1;
      end;
      if not estarted then Exit;
    end
    else
      Exit;
  end;
  if not (started and estarted) then Exit;

  { a dropped nonzero digit past the cap makes the value strictly greater than
    the kept prefix — exactly what a sticky bit is for, and enough to settle any
    tie, since a midpoint has far fewer significant digits than the cap }
  if sticky then DsPush('1');
  SetLength(ds, dsLen);                 { trim the buffer to what was written }

  if dsLen = 0 then                     { all digits were zero }
  begin
    w := 0.0;
    if neg then w := -w;                { preserves -0.0 }
    value := w;
    Result := True;
    Exit;
  end;

  if eneg then e := -e;
  { value = int(ds) * 10^expo }
  expo := e - fracCount;
  { trailing zeros move to the exponent — cheaper, and widens the fast path }
  nd := Length(ds);
  while (nd > 1) and (ds[nd] = '0') do begin nd := nd - 1; expo := expo + 1; end;
  ds := Copy(ds, 1, nd);

  { Fast path (Clinger): with the significand under 2^53 and |expo| <= 22, both
    the significand and 10^|expo| are exactly representable, so a single
    multiply or divide is a single rounding and is therefore already the
    correctly rounded result. 10^k is built by repeated multiplication, which
    is exact up to 10^22 — deliberately not a table of literals, since parsing
    those literals is the very thing being fixed here. Covers the overwhelming
    majority of real input (JSON numbers and the like). }
  if (nd <= 15) and (expo >= -22) and (expo <= 22) then
  begin
    sig := 0;
    for k := 1 to nd do sig := sig * 10 + Int64(Ord(ds[k]) - Ord('0'));
    w := sig * 1.0;
    p := 1.0;
    if expo >= 0 then
    begin
      for k := 1 to expo do p := p * 10.0;
      w := w * p;
    end
    else
    begin
      for k := 1 to -expo do p := p * 10.0;
      w := w / p;
    end;
    if neg then w := -w;
    value := w;
    Result := True;
    Exit;
  end;

  { Eisel-Lemire: one 128-bit multiply for everything Clinger could not reach.
    19 digits is the cap because that is what a u64 significand holds exactly
    (10^19 - 1 < 2^64); past it the significand would have to be truncated, and
    a truncated significand is precisely what this algorithm may not be given.
    A decline falls through to the exact search below and is still right. }
  if nd <= 19 then
  begin
    msig := 0;
    for k := 1 to nd do msig := msig * 10 + UInt64(Ord(ds[k]) - Ord('0'));
    if EiselLemire(msig, expo, w) then
    begin
      if neg then w := -w;
      value := w;
      Result := True;
      Exit;
    end;
  end;

  { Exact reconstruction. decExp is the power of ten the first digit stands for.

    Two implementations of the same correctly-rounded answer. ExBinNearest
    compares in binary big integers and is what Eisel-Lemire's declines land on
    — chiefly the subnormals, which Lemire refuses by construction. It declines
    in turn for anything whose operands would not fit its limb array, and
    ExDecNearest — which compares by expanding each candidate to its exact
    decimal, and has no size limit — answers those. Each layer declines rather
    than guesses, so the composition cannot produce a wrong value, only a slower
    right one. }
  lead := nd - 1 + expo;
  if not ExBinNearest(ds, lead, nd, expo, w) then
    w := ExDecNearest(ds, lead, nd, expo);
  if neg then w := -w;
  value := w;
  Result := True;
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

procedure Delete(var s: AnsiString; index, count: Integer);
var n: Integer;
begin
  n := Length(s);
  if (index < 1) or (index > n) or (count <= 0) then Exit;
  if index + count - 1 > n then count := n - index + 1;
  s := Copy(s, 1, index - 1) + Copy(s, index + count, n);
end;

procedure Insert(const src: AnsiString; var dst: AnsiString; index: Integer);
var n: Integer;
begin
  if src = '' then Exit;
  n := Length(dst);
  if index < 1 then index := 1;
  if index > n + 1 then index := n + 1;
  dst := Copy(dst, 1, index - 1) + src + Copy(dst, index, n);
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

function SameText(const s1, s2: AnsiString): Boolean;
begin
  Result := CompareText(s1, s2) = 0;
end;

function AnsiSameText(const s1, s2: AnsiString): Boolean;
begin
  Result := SameText(s1, s2);
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

{ Same parser as StrToIntDef, so the two cannot answer differently -- this one
  used to Trim() and so accepted a trailing space that StrToIntDef rejected.
  FPC accepts leading whitespace only. }
function TryStrToInt(const s: AnsiString; var value: Integer): Boolean;
var v: Int64;
begin
  Result := ParseIntPrefixed(s, v);
  if Result then value := Integer(v);
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

function QuotedStr(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString;
begin
  r := '''';
  for i := 1 to Length(s) do
  begin
    if s[i] = '''' then r := r + '''''' else r := r + s[i];
  end;
  Result := r + '''';
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
function FmtExponent(v: Double; sig: Integer): AnsiString;
var neg: Boolean; e10: Integer; ds, mant, es: AnsiString;
begin
  { `sig` is significant digits (FPC's rule, min 2); 17 is the most a Double
    can carry, and the default. }
  if sig < 2 then sig := 2;
  if sig > 17 then sig := 17;
  if v <> v then begin FmtExponent := 'NaN'; Exit; end;
  { Infinity BEFORE anything else: the old normalise loop divided by ten until
    the value dropped below ten, and Inf/10.0 is Inf, so it never terminated. }
  if v > 1.7976931348623157e308 then begin FmtExponent := 'Inf'; Exit; end;
  if v < -1.7976931348623157e308 then begin FmtExponent := '-Inf'; Exit; end;
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
  while Length(es) < 3 do es := '0' + es;
  if e10 < 0 then es := '-' + es else es := '+' + es;
  FmtExponent := mant + 'E' + es;
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
      'd', 'u':
        begin
          if argIdx < Length(args) then
            piece := FmtIntPrec(IntToStr(FmtArgInt(args[argIdx])), hasPrec, prec);
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

initialization
  DefaultSystemCodePage := CP_UTF8;   { byte-transparent -- see the declaration }
  BackTraceStrFunc := @SysBackTraceStr;
  AssertErrorProc := @SysAssertError;
  PXXOverflowHook := @SysRaiseOverflow;
  PXXDivZeroHook := @SysRaiseDivByZero;
  PXXRangeErrorHook := @SysRaiseRangeError;
  PXXIoErrorHook := @SysRaiseIoError;
  TimeSeparator := ':';
  DateSeparator := '-';
  ShortDateFormat := 'd/m/y';
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
