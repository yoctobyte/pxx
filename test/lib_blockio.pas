{ BlockRead / BlockWrite at every count-out width FPC publishes.

  THE GUARD COLUMN IS THE TEST. The returned count is correct in every case,
  including the broken one -- what a too-wide write destroys is the caller's
  NEXT local, so an assertion that only checks `got` passes while memory is
  being corrupted. Each case therefore declares a sentinel beside the count and
  requires it to survive, and requires the length variable used to size the
  buffer to survive too: measured 2026-09-16, `BlockRead(f, b[0], n, c)` with
  `n, c: LongInt` returned c=10 and left n=0, and the next statement indexed a
  ten-byte buffer with a zero length.

  IT ALSO PINS THE DECLARATION ORDER IN textfile.pas, WHICH IS LOAD-BEARING
  UNTIL THE COMPILER IS FIXED -- AND IT PINS THE CONDITION, NOT JUST THE
  SYMPTOM. The exact-width row is declared and still loses, but only sometimes:
  a `var` parameter's exact match is honoured exactly when EVERY OTHER argument
  binds with NO conversion, and one by-value argument needing ANY conversion --
  widening or narrowing, variable or literal -- masks it, after which
  declaration order decides. `count` is Int64 in every row, so the ordinary
  `BlockRead(f, b[0], n, c)` with an Integer `n` IS the masking shape. The
  CaseExact* procedures below pass an Int64 length, convert nothing, and are
  correct under BOTH orderings; the CaseLongInt/Integer/Cardinal/Word ones
  convert and are correct only under narrowest-first. That asymmetry is the
  pin -- neither half alone shows it. The real fix is the compiler refusing a
  narrower actual outright, as fpc does
  ("Call by var for arg no. 4 has to match exactly") --
  bug-p-a-var-parameter-accepts-a-narrower-actual-and-writes-past-it.

  Every expected value was measured under fpc 3.2.2 with the same source, not
  written from the specification. }
program lib_blockio;

var ok, total: Integer;
    path: AnsiString;

procedure Chk(cond: Boolean; const what: AnsiString);
begin
  Inc(total);
  if cond then Inc(ok) else WriteLn('FAIL: ', what);
end;

const SENTINEL = 12345678;
      N = 10;

procedure MakeFile;
var f: File of Byte; b: array[0..N-1] of Byte; i: Integer; put: Int64;
begin
  for i := 0 to N - 1 do b[i] := 65 + i;
  Assign(f, path);
  Rewrite(f);
  put := 0;
  BlockWrite(f, b[0], N, put);
  Chk(put = N, 'BlockWrite(Int64) wrote every record');
  Close(f);
end;

function Contents(b: PByte; n: Integer): Boolean;
var i: Integer;
begin
  Result := True;
  for i := 0 to n - 1 do
    if b[i] <> Byte(65 + i) then Result := False;
end;

{ One case per width. The bodies are deliberately identical apart from the
  count variable's type -- that IS the axis under test. }

procedure CaseLongInt;
var f: File of Byte; b: PByte; n, c, guard: LongInt;
begin
  guard := SENTINEL;
  Assign(f, path); Reset(f); n := FileSize(f); GetMem(b, n); c := 0;
  BlockRead(f, b[0], n, c);
  Chk(c = N, 'LongInt: the count came back');
  Chk(n = N, 'LongInt: the LENGTH variable survived the call');
  Chk(guard = SENTINEL, 'LongInt: the adjacent local survived the call');
  Chk(Contents(b, N), 'LongInt: the bytes are right');
  Close(f); FreeMem(b);
end;

procedure CaseInteger;
var f: File of Byte; b: PByte; n, guard: LongInt; c: Integer;
begin
  guard := SENTINEL;
  Assign(f, path); Reset(f); n := FileSize(f); GetMem(b, n); c := 0;
  BlockRead(f, b[0], n, c);
  Chk(c = N, 'Integer: the count came back');
  Chk(n = N, 'Integer: the LENGTH variable survived the call');
  Chk(guard = SENTINEL, 'Integer: the adjacent local survived the call');
  Chk(Contents(b, N), 'Integer: the bytes are right');
  Close(f); FreeMem(b);
end;

procedure CaseCardinal;
var f: File of Byte; b: PByte; n, guard: LongInt; c: Cardinal;
begin
  guard := SENTINEL;
  Assign(f, path); Reset(f); n := FileSize(f); GetMem(b, n); c := 0;
  BlockRead(f, b[0], n, c);
  Chk(c = N, 'Cardinal: the count came back');
  Chk(n = N, 'Cardinal: the LENGTH variable survived the call');
  Chk(guard = SENTINEL, 'Cardinal: the adjacent local survived the call');
  Chk(Contents(b, N), 'Cardinal: the bytes are right');
  Close(f); FreeMem(b);
end;

procedure CaseWord;
var f: File of Byte; b: PByte; n, guard: LongInt; c: Word;
begin
  guard := SENTINEL;
  Assign(f, path); Reset(f); n := FileSize(f); GetMem(b, n); c := 0;
  BlockRead(f, b[0], n, c);
  Chk(c = N, 'Word: the count came back');
  Chk(n = N, 'Word: the LENGTH variable survived the call');
  Chk(guard = SENTINEL, 'Word: the adjacent local survived the call');
  Chk(Contents(b, N), 'Word: the bytes are right');
  Close(f); FreeMem(b);
end;

procedure CaseInt64;
var f: File of Byte; b: PByte; n, guard: LongInt; c: Int64;
begin
  guard := SENTINEL;
  Assign(f, path); Reset(f); n := FileSize(f); GetMem(b, n); c := 0;
  BlockRead(f, b[0], n, c);
  Chk(c = N, 'Int64: the count came back');
  Chk(n = N, 'Int64: the LENGTH variable survived the call');
  Chk(guard = SENTINEL, 'Int64: the adjacent local survived the call');
  Chk(Contents(b, N), 'Int64: the bytes are right');
  Close(f); FreeMem(b);
end;

{ ---- the same call with NOTHING to convert ----

  Identical to the four cases above except that the LENGTH is already Int64, so
  every argument binds exactly. Under the masking rule these must be correct
  whatever order textfile.pas declares its rows in, where the four above are
  correct only narrowest-first. Measured under both orderings, not reasoned. }

procedure CaseExactWord;
var f: File of Byte; b: PByte; n: Int64; guard: LongInt; c: Word;
begin
  guard := SENTINEL;
  Assign(f, path); Reset(f); n := FileSize(f); GetMem(b, n); c := 0;
  BlockRead(f, b[0], n, c);
  Chk(c = N, 'exact/Word: the count came back');
  Chk(n = N, 'exact/Word: the LENGTH variable survived the call');
  Chk(guard = SENTINEL, 'exact/Word: the adjacent local survived the call');
  Close(f); FreeMem(b);
end;

procedure CaseExactLongInt;
var f: File of Byte; b: PByte; n: Int64; guard: LongInt; c: LongInt;
begin
  guard := SENTINEL;
  Assign(f, path); Reset(f); n := FileSize(f); GetMem(b, n); c := 0;
  BlockRead(f, b[0], n, c);
  Chk(c = N, 'exact/LongInt: the count came back');
  Chk(n = N, 'exact/LongInt: the LENGTH variable survived the call');
  Chk(guard = SENTINEL, 'exact/LongInt: the adjacent local survived the call');
  Close(f); FreeMem(b);
end;

procedure CaseExactCardinal;
var f: File of Byte; b: PByte; n: Int64; guard: LongInt; c: Cardinal;
begin
  guard := SENTINEL;
  Assign(f, path); Reset(f); n := FileSize(f); GetMem(b, n); c := 0;
  BlockRead(f, b[0], n, c);
  Chk(c = N, 'exact/Cardinal: the count came back');
  Chk(n = N, 'exact/Cardinal: the LENGTH variable survived the call');
  Chk(guard = SENTINEL, 'exact/Cardinal: the adjacent local survived the call');
  Close(f); FreeMem(b);
end;

{ BlockWrite has the same signature shape and the same hazard, so it gets the
  same treatment rather than being assumed to follow. }
procedure WriteWidths;
var f: File of Byte; b: array[0..N-1] of Byte; i: Integer;
    cw: Word; cl: LongInt; cc: Cardinal; cq: Int64; guard: LongInt;
begin
  for i := 0 to N - 1 do b[i] := 65 + i;
  guard := SENTINEL;
  Assign(f, path); Rewrite(f);
  cw := 0; BlockWrite(f, b[0], N, cw);
  Chk(cw = N, 'BlockWrite Word: the count came back');
  cl := 0; BlockWrite(f, b[0], N, cl);
  Chk(cl = N, 'BlockWrite LongInt: the count came back');
  cc := 0; BlockWrite(f, b[0], N, cc);
  Chk(cc = N, 'BlockWrite Cardinal: the count came back');
  cq := 0; BlockWrite(f, b[0], N, cq);
  Chk(cq = N, 'BlockWrite Int64: the count came back');
  Chk(guard = SENTINEL, 'BlockWrite: the adjacent local survived all four');
  Close(f);
  Assign(f, path); Reset(f);
  Chk(FileSize(f) = 4 * N, 'BlockWrite: all four calls actually reached the file');
  Close(f);
end;

begin
  ok := 0; total := 0;
  if ParamCount < 1 then
  begin
    WriteLn('usage: lib_blockio <scratch-dir>');
    Halt(1);
  end;
  path := ParamStr(1) + '/lib_blockio.dat';

  MakeFile;
  CaseLongInt;
  CaseInteger;
  CaseCardinal;
  CaseWord;
  CaseInt64;
  CaseExactWord;
  CaseExactLongInt;
  CaseExactCardinal;
  WriteWidths;

  WriteLn('total ok ', ok, ' / ', total);
end.
