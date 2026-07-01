program test_nested_proc_sibling_call;
{$mode objfpc}{$H+}

{ bug-nested-proc-sibling-call-unresolved.

  Symptom 1: a nested procedure could not call another procedure declared in
  the same enclosing routine (only calls FROM the enclosing routine's own
  body worked). Covers: a plain sibling call, a captured-variable sibling
  call, a chained sibling call, and a Self-capturing sibling call inside a
  method.

  Symptom 2: a nested procedure that captures an outer variable and recurses
  lost its hidden captured-frame argument at the self-call site (wrong
  arity). Covers: capture + self-recursion, capture + self-recursion + a
  Self-capturing method (the field-prefix-insertion and self-call-splice
  token-insertion passes interacting in the same body -- the trickiest
  combination, and the one that first exposed a bug in the fix), multiple
  captured vars with multiple self-call sites, and a sibling calling a
  capturing self-recursive routine (both symptoms at once). Plain (non-
  capturing) self-recursion is included as a must-not-regress control. }

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

function PlainRecursion(n: integer): integer;
  procedure countdown(k: integer);
  begin
    if k > 0 then begin writeln(k); countdown(k-1); end;
  end;
begin
  countdown(n);
  PlainRecursion := 0;
end;

function CaptureRecursion(n: integer): integer;
  var acc: integer;
  procedure inner(k: integer);
  begin
    if k > 0 then begin acc := acc + k; inner(k-1); end;
  end;
begin
  acc := 0;
  inner(n);
  CaptureRecursion := acc;
end;

function MultiCaptureMultiCallSite(n: integer): integer;
  var acc, calls: integer;
  procedure inner(k: integer);
  begin
    calls := calls + 1;
    if k > 1 then begin acc := acc + k; inner(k-1); end
    else if k = 1 then begin acc := acc + k; inner(0); end;
  end;
  procedure runner;
  begin
    inner(n);
  end;
begin
  acc := 0; calls := 0;
  runner;
  MultiCaptureMultiCallSite := acc * 1000 + calls;
end;

type
  TCounter = class
    total: integer;
    procedure Run(n: integer);
  end;

procedure TCounter.Run(n: integer);
  procedure step(k: integer);
  begin
    if k > 0 then begin total := total + k; step(k-1); end;
  end;
begin
  total := 0;
  step(n);
end;

var
  f: TFoo;
  c: TCounter;
begin
  Basic;
  Captured;
  f := TFoo.Create;
  f.Run;

  writeln(PlainRecursion(3));
  writeln(CaptureRecursion(5));
  writeln(MultiCaptureMultiCallSite(4));

  c := TCounter.Create;
  c.Run(4);
  writeln(c.total);
end.
