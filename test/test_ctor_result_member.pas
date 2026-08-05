{ A selector on a CONSTRUCTOR result. The chain used to be DROPPED at the
  expression-position constructor exit, so an Integer variable received the
  instance POINTER and the program printed garbage with no diagnostic
  (bug-p-member-off-a-constructor-result-yields-garbage).

  The Make() lines are here on purpose: the same shape on an ordinary FUNCTION
  result was always correct, and that is what said the machinery worked and
  only the constructor exit was missing it. }
program test_ctor_result_member;
type
  TThing = class
    n: Integer;
    constructor Create(k: Integer);
    function Val: Integer;
  end;
constructor TThing.Create(k: Integer); begin n := k; end;
function TThing.Val: Integer; begin Result := n; end;
function Make(k: Integer): TThing; begin Result := TThing.Create(k); end;
var a, b, c, d, e: Integer; s: string;
begin
  a := TThing.Create(2).n;
  b := TThing.Create(3).Val;
  c := Make(4).n;
  d := Make(5).Val;
  e := TThing.Create(6).Val + 1;
  s := TThing.Create(7).ClassName;
  writeln(a, '|', b, '|', c, '|', d, '|', e, '|', s);
  if (a = 2) and (b = 3) and (c = 4) and (d = 5) and (e = 7) and (s = 'TThing') then
    writeln('PASS')
  else
    writeln('FAIL');
end.
