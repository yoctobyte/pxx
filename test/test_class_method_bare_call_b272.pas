{ Bare (unqualified) call to a sibling CLASS method, from inside a class method.

  A `class procedure` is STATIC: it has no Self, so CurSelfClass is deliberately
  unset in its body and every implicit-Self dispatch is skipped -- which used to
  leave the name as "undefined variable". But a static method needs no Self: it is
  callable exactly like a plain proc. Resolution keys on CurMethClass (set for both
  method kinds), and only STATIC methods qualify -- an instance method reached from
  a class method has no instance to run on and must keep failing.

  This is fpcunit's TAssert.FailEquals calling Fail. }
program test_class_method_bare_call_b272;

type
  TA = class
    class procedure Helper(const s: string);
    class procedure Go;
    class function Twice(i: Integer): Integer;
    class procedure Over(i: Integer); overload;
    class procedure Over(const s: string); overload;
    class procedure UseOver;
    { instance methods still resolve bare inside INSTANCE methods, via Self }
    v: Integer;
    procedure Show;
    procedure InstGo;
  end;

class procedure TA.Helper(const s: string);
begin
  writeln('helper: ', s);
end;

class function TA.Twice(i: Integer): Integer;
begin
  Result := i * 2;
end;

class procedure TA.Go;
begin
  Helper('from class method');        { bare sibling class method }
  writeln('twice: ', Twice(21));      { ...in an expression, too }
end;

class procedure TA.Over(i: Integer);
begin
  writeln('over int: ', i);
end;

class procedure TA.Over(const s: string);
begin
  writeln('over str: ', s);
end;

class procedure TA.UseOver;
begin
  { overload resolution runs over this method's OWN overload set }
  Over(7);
  Over('seven');
end;

procedure TA.Show;
begin
  writeln('v=', v);
end;

procedure TA.InstGo;
begin
  Show;                                { unchanged: implicit Self }
  Helper('from instance method');      { a class method, called from an instance one }
end;

var a: TA;
begin
  TA.Go;
  TA.UseOver;
  a := TA.Create;
  a.v := 42;
  a.InstGo;
end.
