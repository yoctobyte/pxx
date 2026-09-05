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
    with no such member; `textfile` writes and reads a real file from inside a
    class that shadows `Read`, so the intrinsic is reached from a method that
    IS inside a shadowing class rather than from one that avoids the question.
  * `arity` is the second half of that gate, and it pins a DELIBERATE divergence
    rather than FPC's answer. The class declares a 2-parameter Write; the call
    passes a Text handle and three strings. No member can accept it, so we fall
    through to the intrinsic — fpc 3.2.2 instead refuses the whole unit
    ("Wrong number of parameters specified for call to Write"), because it gives
    the member absolute priority and never falls back. We diverge on purpose:
    lib/rtl/configparser.pas is written in that shape, and the fall-through is
    what bug-p-a-write-call-inside-a-method-named-write-binds-to-the-member-whatever-its-arity
    installed after the un-gated version wrote an EMPTY FILE and returned True
    on x86-64 while refusing to build on three other targets.

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
  end;

  { Shadows Read and NOT Write, so an ordinary Write/Readln on a Text handle
    inside it is the intrinsic reached from a method that shadows a sibling
    name. TStreamish cannot host this row: it declares a 2-parameter Write, and
    `Write(f, 'payload')` matches that arity, so the call binds to the member and
    writes nothing at all -- a silent wrong value, pre-existing (identical on
    pinned), and refused outright by fpc 3.2.2 with "Wrong number of parameters
    specified for call to Write". Its own ticket, not this one's row to assert. }
  TReaderOnly = class
    function Read(var Buffer; Count: Longint): Longint;
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

function TReaderOnly.Read(var Buffer; Count: Longint): Longint;
begin
  Result := Count;
end;

{ Write/Readln on a Text handle from INSIDE a class that shadows Read. }
function TReaderOnly.TextRoundTrip(const path: AnsiString): AnsiString;
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
  ro: TReaderOnly;
  b: array[0..7] of Byte;
  tmpdir: AnsiString;
begin
  ok := 0; tot := 0;
  tmpdir := GetEnvironmentVariable('TMPDIR');
  if tmpdir = '' then tmpdir := '/tmp';
  s := TStreamish.Create;
  ro := TReaderOnly.Create;

  { Read returns Count*2, so it is never < Count for a positive Count }
  ChkS('expr',       s.ViaExpr(b, 4),      'full');
  Chk ('assign',     s.ViaAssign(b, 4),    8);
  Chk ('arg',        s.ViaArg(b, 6),       12);
  Chk ('qualified',  s.ViaQualified(b, 3), 6);
  Chk ('write expr', s.ViaWrite(b, 4),     20);

  s.Console;

  ChkS('textfile intrinsic', ro.TextRoundTrip(tmpdir + '/test_rwname_a.txt'), 'payload');
  Chk ('arity falls through', s.ArityFallsThrough(tmpdir + '/test_rwname_b.txt'), 3);

  writeln('total ok ', ok, ' / ', tot);
end.
