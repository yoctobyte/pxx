program test_a_global_routine_may_be_named_read_or_write;
{$mode objfpc}
{ Read / Write / Readln / Writeln are INTRINSICS RESOLVED BY CONTEXT, not
  reserved words: FPC lets a user declaration shadow them, and pxx refused all
  four at the DECLARATION -- `expected name`, before the name reached the symbol
  table -- at top level and nested alike.

  This test asserts BOTH DIRECTIONS in one program, which is the whole point:
  the four names are declarable AND the console/file intrinsics still win
  everywhere nothing shadows them. A test that only proved the declaration would
  pass over a compiler that had stopped writing to the console.

  Every row was diffed against fpc 3.2.2 -Mobjfpc where fpc accepts the source.
  Three rows it does NOT accept, because FPC's shadowing is TOTAL -- once a
  global `Write` exists, `Write(f, x)` and a wrong-arity console `Write` are
  hard errors there, while we fall through to the intrinsic. Accepting what FPC
  rejects is not a defect (CLAUDE.md), and the fall-through is the SAFE
  direction: it is why no existing console call in any tree can change meaning. }

uses sysutils;

var
  f: Text;
  tmppath: string;
  buf: array[0..7] of Char;
  n: Longint;
  s: string;

{ Declarable at top level, all four spellings. }
function Read(x: LongInt): Boolean;
begin
  Result := x > 0;
end;

function Readln(x: LongInt): LongInt;
begin
  { the own-name result assignment, on a name that lexes as an intrinsic }
  Readln := x + 1;
end;

function Write(const Buffer; Count: Longint): Longint;
begin
  Result := Count * 10;
end;

{ THREE parameters deliberately. A one-parameter user `Writeln` would shadow
  every `writeln('...')` in this very file -- correctly, and FPC does the same --
  and the test would then assert nothing about the console at all while looking
  like it did. Every console call below passes one or two arguments. }
function Writeln(const t: string; a, b: LongInt): LongInt;
begin
  Result := Length(t) + a + b;
end;

{ ...and NESTED, which needs the lift's three rename sites to drop the intrinsic
  token kind along with the spelling: the mangled name `write$N` is not an
  intrinsic spelling, so a token still claiming to be tkwrite is simply lying. }
function nested_writer(k: LongInt): LongInt;

  function Write(v: LongInt): LongInt;
  begin
    Write := v * 3;
  end;

begin
  Result := Write(k) + 1;
end;

begin
  { --- the four user routines are reachable, in EXPRESSION position --- }
  if Read(1) then writeln('read     yes') else writeln('read     no');
  writeln('readln   ', Readln(41));
  n := Write(buf, 7);
  writeln('write    ', n);
  writeln('writeln  ', Writeln('abcde', 10, 20));
  writeln('nested   ', nested_writer(14));

  { --- and the intrinsics still win where nothing shadows them --- }

  { arity: the user Write takes TWO parameters, so a three-argument call is the
    console -- and a one-argument console `writeln` is untouched because the user
    Writeln takes three. This is the gate that keeps every existing console call
    in every existing tree meaning what it meant. }
  Write('con', 'sole', ' ');
  writeln('3-arg');

  { format specifiers still parse }
  write('fmt      '); write(3.14159:8:2); writeln;

  { a FILE HANDLE in first position is the intrinsic whatever the arity says --
    this call matches the 2-parameter user Write on arity, and `const Buffer` is
    untyped so no type probe rejects it either }
  { Same tmpdir resolution as test_typed_file_of_t.pas: TESTMGR_TMP first (the
    only one testmgr's filtered environment passes through), TESTTMP second,
    /tmp last. }
  tmppath := GetEnvironmentVariable('TESTMGR_TMP');
  if tmppath = '' then tmppath := GetEnvironmentVariable('TESTTMP');
  if tmppath = '' then tmppath := '/tmp';
  tmppath := tmppath + '/test_global_write_name.tmp';
  Assign(f, tmppath);
  Rewrite(f);
  writeln(f, 'to-file');
  Write(f, 'and-more');
  writeln(f);
  Close(f);

  Assign(f, tmppath);
  Reset(f);
  readln(f, s);
  writeln('file     ', s);
  readln(f, s);
  writeln('file     ', s);
  Close(f);
  Erase(f);
end.
