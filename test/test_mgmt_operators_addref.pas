program test_mgmt_operators_addref;
{ `class operator AddRef` — the BY-VALUE PARAMETER event, and only that.

  Measured against fpc 3.2.2 before the emitter was written, because the shape
  was not obvious from the name:

  - AddRef runs on the COPY, AFTER the source's bytes are already in it. The
    operator here adds 100 to the field, so `AddRef sees id=7` and the callee
    then sees 107 — that is what says it acts on the destination.
  - The caller's original is untouched (still 7), which is what says it does
    NOT act on the source.
  - The copy is NOT Initialize'd. fpc runs AddRef INSTEAD of Initialize for a
    by-value parameter, never as well — count the Init lines.
  - The copy IS Finalized when the call returns, at 107, i.e. after the
    operator mutated it.
  - A `const` and a `var` parameter run NEITHER operator. Those two rows are the
    controls that make the by-value row mean something: all three pass the same
    record to the same shape of procedure, and only the by-value one fires.

  EVERY LINE BELOW IS FPC 3.2.2's, byte for byte.

  THE RECORD IS DELIBERATELY OVER 8 BYTES. At or under 8 the by-value copy is
  pushed as machine words and has no address for an operator to act on, which
  pxx refuses outright — see test_mgmt_operators_addref_small_refused. A record
  sized under that limit would make this test pass by refusal instead of by
  agreement, which is the failure mode an expected-output test cannot show.

  USES A LOCAL, NOT A GLOBAL, on purpose: pxx finalizes a global record at
  program exit and fpc does not, a known and separate divergence, and a global
  here would have put that difference into every row of this file. }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    id: Integer;
    pad1, pad2, pad3: Int64;   { > 8 bytes: see the header }
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
    class operator AddRef(var a: TFoo);
  end;

class operator TFoo.Initialize(var a: TFoo);
begin a.id := 0; WriteLn('  Init'); end;

class operator TFoo.Finalize(var a: TFoo);
begin WriteLn('  Fin    id=', a.id); end;

class operator TFoo.AddRef(var a: TFoo);
begin WriteLn('  AddRef sees id=', a.id); a.id := a.id + 100; end;

procedure TakeVal(f: TFoo);
begin WriteLn('  callee(byval) id=', f.id); end;

procedure TakeConst(const f: TFoo);
begin WriteLn('  callee(const) id=', f.id); end;

procedure TakeVar(var f: TFoo);
begin WriteLn('  callee(var)   id=', f.id); end;

procedure Run;
var a: TFoo;
begin
  a.id := 7;
  WriteLn('-- by value --');
  TakeVal(a);
  WriteLn('after byval, caller id=', a.id);
  WriteLn('-- const --');
  TakeConst(a);
  WriteLn('after const, caller id=', a.id);
  WriteLn('-- var --');
  TakeVar(a);
  WriteLn('after var,   caller id=', a.id);
  WriteLn('-- leaving scope --');
end;

begin
  Run;
  WriteLn('-- done --');
end.
