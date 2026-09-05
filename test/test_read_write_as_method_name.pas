program test_read_write_as_method_name;
{ An UNQUALIFIED call to a method NAMED Read/Write/Readln/Writeln, in EXPRESSION
  position, binds to the method — not to the console intrinsic.

  This is TStream. `TStream.Read`/`Write` is one of the most-used method pairs in
  the Pascal world, and FPC's own compiler sources stop dead without it:

      procedure TCStream.ReadBuffer(var Buffer; Count: Longint);
        begin
           CStreamError:=0;
           if Read(Buffer,Count)<Count then      { cstreams.pas:227 }
             CStreamError:=102;
        end;

  read/write/readln/writeln are LEXER KEYWORDS here (paslexer.inc), so they are
  not identifiers anywhere an identifier is expected. pasparser_name.inc already
  re-admits them in member-NAME and method-NAME position — which is why the
  DECLARATION and the QUALIFIED calls have always worked — and the statement
  dispatch grew its own arm for the unqualified STATEMENT call. ParseFactorCore
  never got one, so `Read(B,C)` was a working statement and an
  `expected expression` in every expression. That asymmetry is what these rows
  pin.

  WHY THE ROWS ARE THESE ROWS:

  * `expr`, `assign` and `arg` are the three expression positions that failed.
    They return DIFFERENT multiples of Count so a row that bound to the wrong
    member, or to a member at all when it should not have, prints a wrong NUMBER
    rather than merely compiling. A row asserting only "it compiles" would pass
    against a binding that called the wrong thing.
  * `qualified` is the CONTROL for the direction that already worked. The fix
    rewrites a token, so the risk it introduces is to the member path, not away
    from it — `Self.Read` must not become the intrinsic.
  * `console` and `textfile` are the CONTROL FOR THE INTRINSIC, and they are the
    load-bearing ones: the whole change is "sometimes this keyword is a name", so
    a version that always treated it as a name would still pass every row above
    and break every ordinary Write in the language. `console` is a plain method
    with no such member; `textfile` writes and reads a real file from inside the
    class that shadows BOTH names with a MATCHING arity, which is the case that
    routes on the file handle rather than on the arity.
  * `member still wins` is that rule's other direction and it is why the fix is
    a first-ARGUMENT test and not "prefer the intrinsic inside a shadowing
    class". `Read(B, C)` with no handle anywhere must still reach the member.
  * `arity falls through` pins a DELIBERATE divergence rather than FPC's answer,
    and NOTE THAT ITS MECHANISM CHANGED under the routing fix. The call passes a
    Text handle and three strings; it now reaches the intrinsic because the FIRST
    ARGUMENT IS A HANDLE, not because no member could accept four arguments. The
    arity gate still exists and still matters — for a call with NO handle whose
    arity no member accepts — but it is no longer what carries this row. Kept
    because the OUTCOME is the contract and it is the one FPC does not share:
    fpc 3.2.2 refuses the whole unit here ("Wrong number of parameters specified
    for call to Write"), giving the member absolute priority and never falling
    back. We diverge on purpose — lib/rtl/configparser.pas is written in this
    shape, and the fall-through is what
    bug-p-a-write-call-inside-a-method-named-write-binds-to-the-member-whatever-its-arity
    installed after the un-gated version wrote an EMPTY FILE and returned True on
    x86-64 while refusing to build on three other targets.

  BECAUSE OF THAT DIVERGENCE THIS FILE HAS NO FPC ORACLE, and that is stated
  rather than left for a reader to assume: fpc REFUSES to compile it, so there
  is no output to diff. Every expectation here is derived from the language and
  from the two tickets named above, not from a second implementation. The rows
  that DO have an oracle live in test_filemode.pas and test_typed_file_of_t.pas.

  bug-p-an-unqualified-call-to-a-user-routine-named-read-or-write-is-eaten-by-the-intrinsic }
{$MODE OBJFPC}
uses sysutils;

type
  TStreamish = class
    function Read(var Buffer; Count: Longint): Longint;
    function Write(const Buffer; Count: Longint): Longint;
    function ViaExpr(var Buffer; Count: Longint): AnsiString;
    function ViaAssign(var Buffer; Count: Longint): Longint;
    function ViaArg(var Buffer; Count: Longint): Longint;
    function ViaQualified(var Buffer; Count: Longint): Longint;
    function ViaWrite(const Buffer; Count: Longint): Longint;
    procedure Console;
    function ArityFallsThrough(const path: AnsiString): Integer;
    function TextRoundTrip(const path: AnsiString): AnsiString;
  end;

var
  ok, tot: Integer;

procedure Chk(const label_: AnsiString; got, want: Longint);
begin
  Inc(tot);
  if got = want then begin Inc(ok); writeln('ok   ', label_); end
  else writeln('FAIL ', label_, ': got ', got, ' want ', want);
end;

procedure ChkS(const label_, got, want: AnsiString);
begin
  Inc(tot);
  if got = want then begin Inc(ok); writeln('ok   ', label_); end
  else writeln('FAIL ', label_, ': got [', got, '] want [', want, ']');
end;

function TStreamish.Read(var Buffer; Count: Longint): Longint;
begin
  Result := Count * 2;
end;

function TStreamish.Write(const Buffer; Count: Longint): Longint;
begin
  Result := Count * 5;
end;

{ the cstreams.pas shape: the call is a comparison operand }
function TStreamish.ViaExpr(var Buffer; Count: Longint): AnsiString;
begin
  if Read(Buffer, Count) < Count then Result := 'short' else Result := 'full';
end;

function TStreamish.ViaAssign(var Buffer; Count: Longint): Longint;
var n: Longint;
begin
  n := Read(Buffer, Count);
  Result := n;
end;

function TStreamish.ViaArg(var Buffer; Count: Longint): Longint;
begin
  Result := Abs(Read(Buffer, Count));
end;

function TStreamish.ViaQualified(var Buffer; Count: Longint): Longint;
begin
  Result := Self.Read(Buffer, Count);
end;

function TStreamish.ViaWrite(const Buffer; Count: Longint): Longint;
begin
  if Write(Buffer, Count) > Count then Result := Write(Buffer, Count)
  else Result := -1;
end;

procedure TStreamish.Console;
begin
  write('con');
  writeln('sole');
end;

{ Write/Readln on a Text handle from inside the class that shadows BOTH names,
  with a member whose ARITY the call matches exactly. This row lived on a
  separate TReaderOnly class until the routing fix landed, precisely because
  TStreamish could not host it: `Write(f, 'payload')` is two arguments, the
  member takes two, so it bound to the member and the file was created EMPTY at
  exit 0. Folding it back here is the point -- the class that CANNOT host the row
  is the one that proves the fix. }
function TStreamish.TextRoundTrip(const path: AnsiString): AnsiString;
var f: Text; s: AnsiString;
begin
  Assign(f, path); Rewrite(f); Write(f, 'payload'); Close(f);
  Assign(f, path); Reset(f); Readln(f, s); Close(f);
  Result := s;
end;

{ four arguments; the member Write takes two. Must reach the intrinsic. }
function TStreamish.ArityFallsThrough(const path: AnsiString): Integer;
var f: Text; s: AnsiString;
begin
  Assign(f, path); Rewrite(f); Write(f, 'x', 'y', 'z'); Close(f);
  Assign(f, path); Reset(f); Readln(f, s); Close(f);
  Result := Length(s);
end;

var
  s: TStreamish;
  b: array[0..7] of Byte;
  tmpdir: AnsiString;
begin
  ok := 0; tot := 0;
  tmpdir := GetEnvironmentVariable('TMPDIR');
  if tmpdir = '' then tmpdir := '/tmp';
  s := TStreamish.Create;

  { Read returns Count*2, so it is never < Count for a positive Count }
  ChkS('expr',       s.ViaExpr(b, 4),      'full');
  Chk ('assign',     s.ViaAssign(b, 4),    8);
  Chk ('arg',        s.ViaArg(b, 6),       12);
  Chk ('qualified',  s.ViaQualified(b, 3), 6);
  Chk ('write expr', s.ViaWrite(b, 4),     20);

  s.Console;

  ChkS('textfile intrinsic', s.TextRoundTrip(tmpdir + '/test_rwname_a.txt'), 'payload');
  Chk ('member still wins',  s.ViaAssign(b, 5), 10);
  Chk ('arity falls through', s.ArityFallsThrough(tmpdir + '/test_rwname_b.txt'), 3);

  writeln('total ok ', ok, ' / ', tot);
end.
