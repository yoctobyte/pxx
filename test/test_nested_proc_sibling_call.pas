program test_nested_proc_sibling_call;
{$mode objfpc}{$H+}

{ bug-nested-proc-sibling-call-unresolved, symptom 1: a nested procedure could
  not call another procedure declared in the same enclosing routine (only
  calls FROM the enclosing routine's own body worked). Covers: a plain
  sibling call, a captured-variable sibling call, a chained sibling call, and
  a Self-capturing sibling call inside a method. }

procedure Basic;
  procedure a; begin writeln('a'); end;
  procedure b; begin a; end;
begin
  b;
end;

procedure Captured;
  var x: integer;
  procedure a; begin writeln('a', x); end;
  procedure b; begin writeln('b-before'); a; writeln('b-after'); end;
  procedure c; begin b; a; end;
begin
  x := 7;
  c;
end;

type
  TFoo = class
    v: integer;
    procedure Run;
  end;

procedure TFoo.Run;
  procedure a; begin writeln('a', v); end;
  procedure b; begin a; end;
begin
  v := 42;
  b;
end;

var f: TFoo;
begin
  Basic;
  Captured;
  f := TFoo.Create;
  f.Run;
end.
