program test_scalar_misuse_is_refused_fail;
{ Five constructs FPC rejects that used to compile clean here, exit 0, and do
  something silently wrong. Found by a 28-construct sweep whose extra step was
  to RUN each binary -- the run is what separates dialect laxness from a defect.

    for s := 1 to 3     the loop machinery increments the counter's slot, which
                        for a managed string is the HANDLE. Printed the text
                        before the loop and then nothing at all in the small
                        case, and SEGFAULTED in a slightly larger one.
    i[2]                took Syms[i].ElemType -- for a scalar, its own type --
                        and emitted an element load off the variable's address:
                        an out-of-bounds read, -2099249120 as measured.
    New(i)              allocated TypeSize(tyUnknown) bytes and stored the block
                        address INTO the Integer: i came back 264241264.
    Inc(s)              desugared to s := s + 1, took the string CONCAT path,
                        and DESTROYED the variable: 'x' became ''.
    Length(i)           read a [data-8] length header off an Integer's value and
                        answered 1 -- a plausible number, no diagnostic.
    r < 1               compared the record's first qword against 1 and
                        answered off garbage.
    with i do           accepted and inert -- a `with` that scopes nothing is a
                        whole block reading the wrong variables, unremarked.
    F1(1) := 3          emitted the CALL and silently DROPPED the store: the
                        `:= 3` was left for the next statement, where the
                        catch-all skipped it to the `;`.

  All eight must now be reported, in ONE compile (they recover), and no binary
  may be written. Deliberately NOT refused, and asserted silent below: `if i`
  and `while i` over an ordinal, which is the C rule and this dialect's
  documented laxness -- both were re-measured and behave exactly as `i <> 0`,
  so they are laxness and nothing more.
  bug-p-ten-constructs-fpc-rejects-are-accepted-and-silently-wrong }
type TR = record a: Integer; end;
function F1(x: Integer): Integer; begin Result := x; end;
var
  s: AnsiString;
  i, j: Integer;
  b: Boolean;
  r: TR;
begin
  r.a := 1;
  s := 'x';
  i := 5;
  for s := 1 to 3 do WriteLn('body');
  j := i[2];
  New(i);
  Inc(s);
  j := Length(i);
  b := r < 1;
  with i do WriteLn('inert');
  F1(1) := 3;
  if i then WriteLn('lax if');
  while False do WriteLn('lax while');
  WriteLn(j, b);
end.
