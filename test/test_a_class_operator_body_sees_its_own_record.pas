program test_a_class_operator_body_sees_its_own_record;
{$MODE DELPHI}
{ A `class operator TRec.<op>` BODY IS A STATIC METHOD OF TRec, and pxx parsed
  it as a bare global function: the record's own `class var`s, class consts and
  nested types were invisible to it without a qualifier.

    class operator TFoo.Initialize(var a: TFoo);
    begin
      Inc(InitializeCount);      // pascal26: undefined variable
    end;

  ONE ARM OF A THREE-WAY CASE, and the two that worked are what made this read
  as a management-operator gap rather than a scope one: the identical line
  inside an ordinary `procedure TFoo.Bump` and inside a `class procedure
  TFoo.CBump` both resolved. Found through fpc testsuite tmoperator7, which
  stopped at `undefined variable (InitializeCount)` on line 29 and was skipped
  as a management-operator row for it.

  THE `bump` AND `cbump` ROWS ARE NOT DECORATION -- they are the two arms that
  were already right, and a fix that reached the operator by breaking either of
  them would pass a test that only had the operator row.

  CurSelfClass is deliberately NOT set for an operator body: a class operator is
  STATIC, so there is no instance. The `Self` row below is the control for that
  half -- a bare FIELD name must NOT resolve in an operator body, and fpc agrees
  (it reports the same shape), so the field is reached through the operator's
  own `var` parameter, which is the only object in scope.

  Every line of output is fpc 3.2.2's own. }

type
  TInner = record
    K: Integer;
  end;

  TFoo = record
  public
    I: Integer;
    class var Count: Integer;
    const Bump = 7;                 { a class CONST, same lookup path }
    type TAlias = TInner;           { a NESTED type, same lookup path }
    procedure Add1;
    class procedure Add10; static;
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
  end;

procedure TFoo.Add1;
begin
  Inc(Count);                       { the arm that already worked }
end;

class procedure TFoo.Add10;
begin
  Inc(Count, 10);                   { the other arm that already worked }
end;

class operator TFoo.Initialize(var a: TFoo);
var
  n: TAlias;                        { the nested type, unqualified }
begin
  Inc(Count, 100);                  { THE ARM THAT DID NOT }
  n.K := Bump;                      { the class const, unqualified }
  a.I := n.K;                       { ...through the operator's own parameter }
end;

class operator TFoo.Finalize(var a: TFoo);
begin
  Inc(Count, 1000);
end;

procedure Scope;
var
  f: TFoo;
begin
  f.Add1;
  writeln('in scope  I=', f.I, ' Count=', TFoo.Count);
end;

begin
  writeln('start     Count=', TFoo.Count);
  Scope;
  TFoo.Add10;
  writeln('after     Count=', TFoo.Count);
end.
