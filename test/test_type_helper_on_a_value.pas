{ Type-helper methods on a receiver that is a VALUE, not a declared variable.

  The dispatch used to key on the receiver SYMBOL, so only a plain variable
  worked: a literal, a call result, a grouped expression and a chained helper
  result were all refused — and two of them were WRONG rather than refused
  (`s.Twice.Twice` printed 24929, `(F).Twice` printed 113;
  bug-p-a-member-on-a-computed-value-silently-reads-the-values-own-bytes).

  A helper method's Self is BY REFERENCE, so the receiver needs an addressable
  home. A computed value gets a hidden local bound once — which is also what
  makes it evaluate exactly once: the `n` counter at the end is the assertion
  that `F.Twice.Twice` calls F a single time.

  A VARIABLE receiver deliberately keeps the old path, taking the address of
  the variable itself: `s.Bang` must write through, and the first row is what
  pins that.

  Expected output is fpc 3.2.2 (-Mobjfpc -O1, {$modeswitch typehelpers}).
  feature-p-delphi-string-helpers }
{$mode objfpc}{$H+}{$modeswitch typehelpers}
program test_type_helper_on_a_value;
type
  TSH = type helper for string
    procedure Bang;
    function Twice: string;
    function IsEmpty: Boolean;
  end;
  TIH = type helper for Integer
    function Sq: Integer;
    procedure Inc2;
  end;
procedure TSH.Bang; begin Self := Self + '!'; end;
function TSH.Twice: string; begin Result := Self + Self; end;
function TSH.IsEmpty: Boolean; begin Result := System.Length(Self) = 0; end;
function TIH.Sq: Integer; begin Result := Self * Self; end;
procedure TIH.Inc2; begin Self := Self + 2; end;

var s: string; a: AnsiString; i, n: Integer;
function F: string; begin Inc(n); Result := 'q'; end;
function G: Integer; begin Result := 5; end;

begin
  n := 0;
  { a VARIABLE receiver — the by-ref Self must still write through }
  s := 'x'; s.Bang; Writeln(s);
  i := 3; i.Inc2; Writeln(i);
  { the ordinary variable reads }
  s := 'a'; a := 'b';
  Writeln(s.Twice);
  Writeln(a.Twice);
  Writeln(s.IsEmpty);
  Writeln(i.Sq);
  { CHAINED — a helper result is a value, and the chain must keep going }
  Writeln(s.Twice.Twice);
  Writeln(s.Twice.Twice.IsEmpty);
  Writeln(i.Sq.Sq);
  { a GROUPED expression }
  Writeln((F).Twice);
  Writeln((s + 'x').Twice);
  { a string LITERAL — its node is frozen tyString, and the helper targets
    AnsiString; binding to the receiver's own kind printed nothing at all }
  Writeln('xy'.Twice);
  Writeln('xy'.Twice.Twice);
  Writeln(''.IsEmpty);
  { a bare CALL RESULT, the shape that never reaches an lvalue path }
  Writeln(F.Twice);
  Writeln(F.Twice.Twice);
  Writeln(Copy(s, 1, 1).Twice);
  Writeln(G.Sq);
  { …and F ran once per occurrence, not once per mention of Self }
  Writeln(n);
end.
