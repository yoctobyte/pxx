{ SPDX-License-Identifier: Zlib }
unit sysutils;
{ Canonical SysUtils-style helpers. Now that the compiler loads a real
  lib/rtl/sysutils on `uses sysutils` (bug-sysutils-unit-hard-skipped fixed,
  v10), the conversion helpers live here -- their FPC-correct home -- rather than
  the interim lib/rtl/strutils. Pure Pascal, FPC-compatible names. Track B. }

interface

type
  { FPC's SysUtils character set — the parameter type of the CharInSet / character
    classification family, and what real code writes for `set of char` work
    (`cset: TSysCharSet; Include(cset, c)`). It was simply missing, so any unit using it
    failed to compile with "unknown type" (tset4). }
  TSysCharSet = set of AnsiChar;

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

  { pylib's Python root is a DIFFERENT class now — `PyException`
    (decide-pylib-exception-vs-sysutils-exception option 5) — so this
    declaration is free again: it no longer has to match pylib's member for
    member, and neither unit blocks the other from growing.

    ONE contract survives, and it is narrow: `msg` stays the FIRST field. A
    NilPy `except Exception:` bridges to this class as well (Python's root
    catches everything a program can raise, and an RTL raise is still that), so
    the binder reads the message through pylib's class layout. First field,
    same type — that is all the bridge needs, and it is the only coupling left. }
  Exception = class
    msg: string;
    FHelpContext: Integer;
    constructor Create(const msg: string);
    constructor CreateFmt(const msg: string; const args: array of const);
    property HelpContext: Integer read FHelpContext write FHelpContext;
    property FMessage: string read msg write msg;
    property Message: string read msg write msg;
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
  gives fixed-point with precision digits after the decimal point. }
function FloatToStr(value: Double): AnsiString;
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

{ String -> float. StrToFloatDef returns def on malformed; StrToFloat returns 0. }
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

{ Parse "hh[:nn[:ss]]" (TimeSeparator-separated) into a time-of-day fraction.
  Raises Exception on malformed input (FPC raises EConvertError; callers like
  Synapse just catch Exception). No AM/PM, no milliseconds — extend on demand. }
function StrToTime(const S: string): TDateTime;

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

uses platform, platform_types;

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

function TryStrToFloat(const s: AnsiString; var value: Double): Boolean;
var a, b: Double;
begin
  a := StrToFloatDef(s, 0.0);
  b := StrToFloatDef(s, 1.0);
  Result := (a = b);
  if Result then value := a;
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
  n, i, k, fracDigits: Integer;
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
  { top limb unpadded (that is what drops the leading zeros), the rest padded
    to the full nine so limb boundaries do not swallow interior zeros }
  ds := IntToStr(buf[n - 1]);
  for i := n - 2 downto 0 do
  begin
    lp := IntToStr(buf[i]);
    while Length(lp) < 9 do lp := '0' + lp;
    ds := ds + lp;
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

function StrToFloatDef(const s: AnsiString; def: Double): Double;
const
  { every digit past this is beyond any midpoint's ~1080, so it can only break
    a tie — which the sticky digit below does, without unbounded strings }
  EXDEC_INMAX = 1200;
var i, digit, e, k: Integer; c: Char; neg, eneg: Boolean;
    w, p: Double; in_frac, started, estarted, sticky: Boolean;
    ds: AnsiString; fracCount, nd, expo, lead: Integer; sig: Int64;
begin
  Result := def;
  i := 1; neg := False; w := 0.0; in_frac := False; started := False;
  ds := ''; fracCount := 0; sticky := False;
  while (i <= Length(s)) and (s[i] = ' ') do i := i + 1;
  if (i <= Length(s)) and ((s[i] = '-') or (s[i] = '+')) then
  begin
    if s[i] = '-' then neg := True;
    i := i + 1;
  end;
  e := 0; eneg := False; estarted := True;
  while i <= Length(s) do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') then
    begin
      digit := Ord(c) - Ord('0');
      if in_frac then fracCount := fracCount + 1;
      { keep the digits themselves; the value is reconstructed exactly below }
      if Length(ds) < EXDEC_INMAX then
      begin
        if (ds <> '') or (digit <> 0) then ds := ds + c;   { drop leading zeros }
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
      if (i <= Length(s)) and ((s[i] = '-') or (s[i] = '+')) then
      begin
        if s[i] = '-' then eneg := True;
        i := i + 1;
      end;
      estarted := False;
      while i <= Length(s) do
      begin
        c := s[i];
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
  if sticky then ds := ds + '1';

  if ds = '' then                       { all digits were zero }
  begin
    w := 0.0;
    if neg then w := -w;                { preserves -0.0 }
    Result := w;
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
    Result := w;
    Exit;
  end;

  { Slow path: exact reconstruction. decExp is the power of ten the first digit
    stands for. }
  lead := nd - 1 + expo;
  w := ExDecNearest(ds, lead, nd, expo);
  if neg then w := -w;
  Result := w;
end;

function StrToFloat(const s: AnsiString): Double;
begin
  Result := StrToFloatDef(s, 0.0);
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

function StrToTime(const S: string): TDateTime;
var
  part: array[0..2] of Integer;
  np, i, v, digits: Integer;
  c: Char;
begin
  part[0] := 0; part[1] := 0; part[2] := 0;
  np := 0;
  v := 0;
  digits := 0;
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if (c >= '0') and (c <= '9') then
    begin
      v := v * 10 + (Ord(c) - Ord('0'));
      digits := digits + 1;
    end
    else if (c = TimeSeparator) and (np < 2) and (digits > 0) then
    begin
      part[np] := v;
      np := np + 1;
      v := 0;
      digits := 0;
    end
    else if c <> ' ' then
      raise Exception.Create('StrToTime: invalid time string');
  end;
  if digits = 0 then raise Exception.Create('StrToTime: invalid time string');
  part[np] := v;
  if (part[0] > 23) or (part[1] > 59) or (part[2] > 59) then
    raise Exception.Create('StrToTime: invalid time string');
  Result := EncodeTime(part[0], part[1], part[2], 0);
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
