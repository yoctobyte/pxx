{ --fpc-mem-errors: a memory fault reports FPC's runtime error 216 and exits
  216, instead of dying on the kernel default with no message and exit 139.

  One source, five faults, selected by argv[1], because the assertion is per
  fault SHAPE and each one has to be the last thing the process does. Every mode
  prints `before` first, so the test also proves the fault happened where it was
  supposed to and not earlier.

  Run WITHOUT the flag every one of these dies silently with exit 139 — that is
  the bug this file pins (bug-a-a-memory-fault-is-a-raw-sigsegv-not-runtime-
  error-216), and the Makefile asserts both halves.

  Modes: nilread, nilwrite, nilproc, nilmethod, wildstore. }
program test_fpc_mem_errors;
{$mode objfpc}{$H+}

type
  TProc = procedure;
  TBase = class
    procedure Hi; virtual;
  end;

procedure TBase.Hi; begin writeln('hi'); end;

var
  mode: AnsiString;
  p: ^Integer;
  f: TProc;
  o: TBase;
  a: array[0..3] of Integer;
  wild: Integer;

begin
  mode := ParamStr(1);
  writeln('before');
  if mode = 'nilread' then
  begin
    p := nil;
    writeln(p^);
  end
  else if mode = 'nilwrite' then
  begin
    p := nil;
    p^ := 1;
  end
  else if mode = 'nilproc' then
  begin
    f := nil;
    f();
  end
  else if mode = 'nilmethod' then
  begin
    o := nil;
    o.Hi;
  end
  else if mode = 'wildstore' then
  begin
    { A subscript far outside the object, through a variable so no constant
      folding can turn it into a compile-time refusal. }
    wild := 100000000;
    a[wild] := 5;
  end
  else
    writeln('unknown mode: ', mode);
  writeln('after');
end.
