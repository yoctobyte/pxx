unit sysutils;
{ Canonical SysUtils-style helpers. Now that the compiler loads a real
  lib/rtl/sysutils on `uses sysutils` (bug-sysutils-unit-hard-skipped fixed,
  v10), the conversion helpers live here -- their FPC-correct home -- rather than
  the interim lib/rtl/strutils. Pure Pascal, FPC-compatible names. Track B. }

interface

type
  TFileInfo = record
    Name: AnsiString;
    IsDir: Boolean;
    Size: Int64;
    ModifiedTime: Int64;
  end;
  TFileInfoArray = array of TFileInfo;

  TReplaceFlag  = (rfReplaceAll, rfIgnoreCase);
  TReplaceFlags = set of TReplaceFlag;

  Exception = class
    FMessage: string;
    FHelpContext: Integer;
    constructor Create(const msg: string);
    property HelpContext: Integer read FHelpContext write FHelpContext;
    property Message: string read FMessage write FMessage;
  end;

{ Int64 -> decimal string (covers Integer via widening). Handles negatives. }
function IntToStr(value: Int64): AnsiString;

{ Uppercase hexadecimal of value, left-zero-padded to at least Digits chars
  (FPC SysUtils.IntToHex). Negative values use their two's-complement bits. }
function IntToHex(value: Int64; digits: Integer): AnsiString;

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

{ NOTE: no Val here -- `Val` is an intercepted builtin name and the builtin
  mis-lowers (wrong error code + segfault); a user Val is shadowed by it. See
  bug-builtin-val-miscompiles. Use StrToIntDef / StrToInt instead. }

{ ASCII case conversion. }
function UpCase(c: Char): Char;
function UpperCase(const s: AnsiString): AnsiString;
function LowerCase(const s: AnsiString): AnsiString;

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
function StrLCopy(Dest, Source: PChar; MaxLen: Cardinal): PChar;
function StrLComp(Str1, Str2: PChar; MaxLen: Cardinal): Integer;

{ Suspend the current thread for at least Milliseconds (FPC SysUtils.Sleep).
  Backed by the nanosleep syscall. }
procedure Sleep(Milliseconds: Cardinal);

{ INTERIM HOME (see feature-move-fillchar-intrinsics). In FPC, Move/FillChar are
  System primitives — bare, no `uses`. Until the compiler provides them (as
  builtins, then optimized intrinsics) they live here in SysUtils: every real
  consumer, and all Synapse units, `uses SysUtils`, so the bare name resolves.
  Remove from here once the compiler builtin lands. Move is overlap-safe
  (memmove semantics); FillChar fills bytes. }
procedure Move(const Source; var Dest; Count: Integer);
procedure FillChar(var X; Count: Integer; Value: Byte);

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
function SameText(const s1, s2: AnsiString): Boolean;

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

{ List directory entries, excluding "." and "..". Size and modification time are
  filled when the active PAL backend supports metadata, otherwise Size is -1. }
function GetDirectoryContents(const path: AnsiString; var list: TFileInfoArray): Boolean;

{ Execute a process in a pipeline, returning its PID and redirecting stdin/stdout via pipes if requested. }
function ExecutePipeline(const cmd: AnsiString; const args: array of AnsiString; var childStdinFd, childStdoutFd: Integer): Integer;

implementation

uses platform, platform_types;

constructor Exception.Create(const msg: string);
begin
  FMessage := msg;
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
var i, n, last: Integer; r: AnsiString;
begin
  n := Length(s);
  if index < 1 then index := 1;
  if count < 0 then count := 0;
  last := index + count - 1;
  if last > n then last := n;
  r := '';
  i := index;
  while i <= last do
  begin
    r := r + s[i];
    i := i + 1;
  end;
  Result := r;
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
  Result := StrToIntDef(s, 0);
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

procedure Move(const Source; var Dest; Count: Integer);
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

procedure FillChar(var X; Count: Integer; Value: Byte);
var d: PByte; i: Integer;
begin
  d := PByte(@X);
  for i := 0 to Count - 1 do d[i] := Value;
end;

function UpperCase(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString; c: Char;
begin
  r := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'a') and (c <= 'z') then c := Chr(Ord(c) - 32);
    r := r + c;
  end;
  Result := r;
end;

function LowerCase(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString; c: Char;
begin
  r := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    r := r + c;
  end;
  Result := r;
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
var i, digit: Integer; c: Char; neg: Boolean; w, frac, divsor: Double; in_frac: Boolean; started: Boolean;
begin
  Result := def;
  i := 1; neg := False; w := 0.0; frac := 0.0; divsor := 1.0; in_frac := False; started := False;
  while (i <= Length(s)) and (s[i] = ' ') do i := i + 1;
  if (i <= Length(s)) and ((s[i] = '-') or (s[i] = '+')) then
  begin
    if s[i] = '-' then neg := True;
    i := i + 1;
  end;
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
    else
      Exit;
  end;
  if not started then Exit;
  if neg then
    Result := -(w + frac)
  else
    Result := w + frac;
end;

function StrToFloat(const s: AnsiString): Double;
begin
  Result := StrToFloatDef(s, 0.0);
end;

function PadLeft(const s: AnsiString; len: Integer; ch: Char): AnsiString;
var r: AnsiString; i, n: Integer;
begin
  n := Length(s);
  if n >= len then begin Result := s; Exit; end;
  r := '';
  for i := 1 to len - n do r := r + ch;
  Result := r + s;
end;

function PadRight(const s: AnsiString; len: Integer; ch: Char): AnsiString;
var r: AnsiString; i, n: Integer;
begin
  n := Length(s);
  if n >= len then begin Result := s; Exit; end;
  r := s;
  for i := 1 to len - n do r := r + ch;
  Result := r;
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

function SameText(const s1, s2: AnsiString): Boolean;
begin
  Result := CompareText(s1, s2) = 0;
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

function StringReplace(const S, OldPattern, NewPattern: AnsiString; Flags: TReplaceFlags): AnsiString;
var
  src, pat, r: AnsiString;
  i, plen, slen: Integer;
  all, ci, matched: Boolean;
begin
  plen := Length(OldPattern);
  if plen = 0 then begin Result := S; Exit; end;
  all := rfReplaceAll in Flags;
  ci := rfIgnoreCase in Flags;
  if ci then begin src := LowerCase(S); pat := LowerCase(OldPattern); end
  else begin src := S; pat := OldPattern; end;
  slen := Length(S);
  r := '';
  i := 1;
  while i <= slen do
  begin
    matched := (i + plen - 1 <= slen) and (Copy(src, i, plen) = pat);
    if matched then
    begin
      r := r + NewPattern;
      i := i + plen;
      if not all then
      begin
        r := r + Copy(S, i, slen - i + 1);
        Result := r;
        Exit;
      end;
    end
    else
    begin
      r := r + S[i];
      Inc(i);
    end;
  end;
  Result := r;
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

end.
