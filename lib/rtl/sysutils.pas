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

  Exception = class
    FMessage: string;
    FHelpContext: Integer;
    constructor Create(const msg: string);
    constructor CreateFmt(const msg: string; const args: array of const);
    property HelpContext: Integer read FHelpContext write FHelpContext;
    property Message: string read FMessage write FMessage;
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
  (FPC SysUtils.IntToHex). Negative values use their two's-complement bits. }
function IntToHex(value: Int64; digits: Integer): AnsiString;

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

type
  { FPC Currency is a fixed-point 4-decimal Int64; this RTL models it as
    Double (lossy past 2^52 — acceptable for the compat surface;
    Pascal Script's CurrToStr). }
  Currency = Double;

function CurrToStr(C: Currency): AnsiString;

{ Float -> string. FloatToStr gives a compact representation; FloatToStrF
  gives fixed-point with precision digits after the decimal point. }
function FloatToStr(value: Double): AnsiString;
function FloatToStrF(value: Double; precision: Integer): AnsiString;

{ String -> float. StrToFloatDef returns def on malformed; StrToFloat returns 0. }
function StrToFloatDef(const s: AnsiString; def: Double): Double;
function StrToFloat(const s: AnsiString): Double;

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
var a, b: Int64;
begin
  a := StrToInt64Def(s, 0);
  b := StrToInt64Def(s, 1);
  Result := (a = b);
  if Result then value := a;
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
  if neg then value := -value;
  s := '';
  while value > 0 do
  begin
    d := value mod 10;
    s := Chr(Ord('0') + Integer(d)) + s;
    value := value div 10;
  end;
  if neg then s := '-' + s;
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

function StrToIntDef(const s: AnsiString; def: Integer): Integer;
var v, i, sign: Integer; c: Char; started: Boolean;
begin
  Result := def;
  v := 0; sign := 1; i := 1; started := False;
  while (i <= Length(s)) and (s[i] = ' ') do i := i + 1;
  if (i <= Length(s)) and ((s[i] = '-') or (s[i] = '+')) then
  begin
    if s[i] = '-' then sign := -1;
    i := i + 1;
  end;
  while i <= Length(s) do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') then
    begin
      v := v * 10 + (Ord(c) - Ord('0'));
      started := True;
      i := i + 1;
    end
    else
      Exit;            { malformed -> def }
  end;
  if started then Result := sign * v;
end;

function StrToInt(const s: AnsiString): Integer;
begin
  { FPC parity: raises EConvertError on malformed input (used to return 0). }
  if not TryStrToInt(s, Result) then
    raise EConvertError.CreateFmt('"%s" is an invalid integer', [s]);
end;

function StrToInt64Def(const s: AnsiString; def: Int64): Int64;
var
  v: Int64;
  i, sign: Integer;
  c: Char;
  started: Boolean;
begin
  Result := def;
  v := 0; sign := 1; i := 1; started := False;
  while (i <= Length(s)) and (s[i] = ' ') do i := i + 1;
  if (i <= Length(s)) and ((s[i] = '-') or (s[i] = '+')) then
  begin
    if s[i] = '-' then sign := -1;
    i := i + 1;
  end;
  while i <= Length(s) do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') then
    begin
      v := v * 10 + (Ord(c) - Ord('0'));
      started := True;
    end
    else
      Exit;
    i := i + 1;
  end;
  if started then Result := sign * v;
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
  if m = 0 then begin Result := 1; Exit; end;
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

function FloatToStr(value: Double): AnsiString;
var intPart, fracPart: Int64; neg: Boolean; s, fs: AnsiString; i: Integer;
begin
  if value <> value then begin Result := 'NaN'; Exit; end;
  neg := value < 0.0;
  if neg then value := -value;
  intPart := Trunc(value);
  fracPart := Round(Frac(value) * 1000000);
  if fracPart >= 1000000 then begin intPart := intPart + 1; fracPart := 0; end;
  s := IntToStr(intPart);
  if fracPart > 0 then
  begin
    fs := IntToStr(fracPart);
    { left-pad fractional digits to 6 places }
    while Length(fs) < 6 do fs := '0' + fs;
    { trim trailing zeros }
    i := Length(fs);
    while (i > 0) and (fs[i] = '0') do i := i - 1;
    fs := Copy(fs, 1, i);
    s := s + '.' + fs;
  end;
  if neg then s := '-' + s;
  Result := s;
end;

function CurrToStr(C: Currency): AnsiString;
begin
  Result := FloatToStr(C);
end;

function FloatToStrF(value: Double; precision: Integer): AnsiString;
var scale: Double; intPart, fracPart: Int64; neg: Boolean; s, fs: AnsiString; i: Integer;
begin
  if precision < 0 then precision := 0;
  if value <> value then begin Result := 'NaN'; Exit; end;
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
var i, digit, e, k: Integer; c: Char; neg, eneg: Boolean;
    w, frac, divsor, scale: Double; in_frac, started, estarted: Boolean;
begin
  Result := def;
  i := 1; neg := False; w := 0.0; frac := 0.0; divsor := 1.0; in_frac := False; started := False;
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
      if in_frac then
      begin
        divsor := divsor * 10.0;
        frac := frac + (digit * 1.0 / divsor);
      end
      else
        w := w * 10.0 + digit * 1.0;
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
  scale := 1.0;
  for k := 1 to e do scale := scale * 10.0;
  if eneg then
    w := (w + frac) / scale
  else
    w := (w + frac) * scale;
  if neg then
    Result := -w
  else
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

function TryStrToInt(const s: AnsiString; var value: Integer): Boolean;
var i, n, sign, d: Integer; t: AnsiString; v: Int64;
begin
  t := Trim(s);
  n := Length(t);
  if n = 0 then begin Result := False; Exit; end;
  i := 1; sign := 1;
  if t[1] = '-' then begin sign := -1; i := 2; end
  else if t[1] = '+' then i := 2;
  if i > n then begin Result := False; Exit; end;
  v := 0;
  while i <= n do
  begin
    if (t[i] < '0') or (t[i] > '9') then begin Result := False; Exit; end;
    d := Ord(t[i]) - Ord('0');
    v := v * 10 + d;
    Inc(i);
  end;
  value := Integer(sign * v);
  Result := True;
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

function ExtractFileExt(const path: AnsiString): AnsiString;
var i, sep: Integer;
begin
  Result := '';
  sep := LastPathSep(path);
  for i := Length(path) downto sep + 1 do
    if path[i] = '.' then begin Result := Copy(path, i, Length(path) - i + 1); Exit; end;
end;

function ChangeFileExt(const path, ext: AnsiString): AnsiString;
var i, sep: Integer;
begin
  sep := LastPathSep(path);
  for i := Length(path) downto sep + 1 do
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

{ Fixed-point: exactly prec fraction digits, rounded (printf %f). }
function FmtFixed(v: Double; prec: Integer): AnsiString;
var neg: Boolean; ip, scaled, k: Int64; i: Integer; fracStr: AnsiString;
begin
  neg := v < 0;
  if neg then v := -v;
  k := 1;
  for i := 1 to prec do k := k * 10;
  scaled := Trunc(v * k + 0.5);            { round half up }
  ip := scaled div k;
  Result := IntToStr(ip);
  if prec > 0 then
  begin
    fracStr := IntToStr(scaled mod k);
    while Length(fracStr) < prec do fracStr := '0' + fracStr;
    Result := Result + '.' + fracStr;
  end;
  if neg then Result := '-' + Result;
end;

function FmtPad(const s: AnsiString; width: Integer; leftAlign, zeroPad: Boolean): AnsiString;
var pad: AnsiString; need, k: Integer;
begin
  need := width - Length(s);
  if need <= 0 then begin Result := s; Exit; end;
  pad := '';
  if leftAlign then
    for k := 1 to need do pad := pad + ' '
  else if zeroPad then
    for k := 1 to need do pad := pad + '0'
  else
    for k := 1 to need do pad := pad + ' ';
  if leftAlign then Result := s + pad else Result := pad + s;
end;

function Format(const fmt: AnsiString; const args: array of const): AnsiString;
var
  i, n, argIdx, width, prec: Integer;
  c: Char;
  leftAlign, zeroPad, hasPrec: Boolean;
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

    leftAlign := False; zeroPad := False;
    while (i <= n) and ((fmt[i] = '-') or (fmt[i] = '0')) do
    begin
      if fmt[i] = '-' then leftAlign := True else zeroPad := True;
      Inc(i);
    end;
    width := 0;
    while (i <= n) and (fmt[i] >= '0') and (fmt[i] <= '9') do
    begin width := width * 10 + (Ord(fmt[i]) - Ord('0')); Inc(i); end;
    hasPrec := False; prec := 0;
    if (i <= n) and (fmt[i] = '.') then
    begin
      Inc(i); hasPrec := True;
      while (i <= n) and (fmt[i] >= '0') and (fmt[i] <= '9') do
      begin prec := prec * 10 + (Ord(fmt[i]) - Ord('0')); Inc(i); end;
    end;
    if i > n then Break;
    c := fmt[i]; Inc(i);

    piece := '';
    case c of
      'd', 'u':
        begin
          if argIdx < Length(args) then piece := IntToStr(FmtArgInt(args[argIdx]));
          Inc(argIdx);
        end;
      'x', 'X':
        begin
          if argIdx < Length(args) then
          begin iv := FmtArgInt(args[argIdx]); piece := IntToHex(iv, 0); end;
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
          if argIdx < Length(args) then piece := FloatToStr(FmtArgFloat(args[argIdx]));
          Inc(argIdx);
        end;
      'c':
        begin
          if argIdx < Length(args) then piece := Chr(Integer(FmtArgInt(args[argIdx])));
          Inc(argIdx);
        end;
    else
      piece := '%' + c;                            { unknown spec — emit literally }
    end;
    r := r + FmtPad(piece, width, leftAlign, zeroPad);
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
  env: array[0..0] of PChar;
begin
  stdinPipe[0] := -1; stdinPipe[1] := -1;
  stdoutPipe[0] := -1; stdoutPipe[1] := -1;

  { Construct argv in the parent process, before vfork! }
  SetLength(argv, Length(args) + 2);
  argv[0] := PChar(cmd);
  for i := 0 to Length(args) - 1 do
    argv[i + 1] := PChar(args[i]);
  argv[Length(args) + 1] := nil;

  env[0] := nil;

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
  pid := PalVforkAndExec(PChar(cmd), @argv[0], @env[0], stdinPipe[0], stdinPipe[1], stdoutPipe[0], stdoutPipe[1]);

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
  PXXOverflowHook := @SysRaiseOverflow;
  PXXDivZeroHook := @SysRaiseDivByZero;
  PXXRangeErrorHook := @SysRaiseRangeError;
  PXXIoErrorHook := @SysRaiseIoError;
  TimeSeparator := ':';
  DateSeparator := '-';
  DecimalSeparator := '.';
end.
