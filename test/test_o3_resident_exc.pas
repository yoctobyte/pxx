{ -O3 residency vs the setjmp/longjmp exception path.

  The frame slot of a register-resident local has exactly ONE reader that is
  not residency-aware: the IR_EXC_ENTER landing pad, which reloads every
  resident from its slot before entering a handler. It exists because
  ExcSetJmp saves r12-r15 (aarch64: x19-x24) into the jmp_buf and ExcLongJmp
  restores them, so a raise ROLLS A RESIDENT REGISTER BACK to its value at
  try-entry. The slot is the only place the newer value survives.

  That makes the interesting axis "was the resident written INSIDE the
  protected region", not "does this proc contain a try":

    written inside  -> the register is stale after the rollback, the slot is
                       the authority, and the landing-pad refresh is load-bearing
    not written inside -> try-entry value IS the current value, the register is
                       already correct, and the refresh is a no-op

  Every case below is a loop-hot local (so it is a residency candidate) in a
  proc with an exception frame, arranged so the two classes are distinguishable
  in the output. Run at -O0/-O1/-O2/-O3: all four must agree. }
program test_o3_resident_exc;
uses SysUtils;

var
  gSink: LongInt;

procedure Boom;
begin
  raise Exception.Create('x');
end;

{ Written OUTSIDE the try, read inside it. The rollback restores the same
  value the register already held, so nothing here needs the slot. }
procedure OutsideOnly;
var i, acc, seen: LongInt;
begin
  acc := 0; seen := -1;
  for i := 1 to 200 do
  begin
    acc := acc + i;
    try
      if i = 137 then Boom;
    except
      seen := acc;          { acc must be the sum through 137 }
    end;
  end;
  Writeln('OUT i=', i, ' acc=', acc, ' seen=', seen);
end;

{ Written INSIDE the try. The register is rolled back to the try-entry value;
  only the slot carries the newer one. }
procedure InsideOnly;
var i, acc, seen: LongInt;
begin
  acc := 0; seen := -1;
  for i := 1 to 200 do
  begin
    try
      acc := acc + i;       { inside -> rolled back on the raise }
      if i = 137 then Boom;
    except
      seen := acc;          { must still be the sum through 137 }
    end;
  end;
  Writeln('IN  i=', i, ' acc=', acc, ' seen=', seen);
end;

{ Both classes in one body, so a per-symbol rule is distinguishable from a
  per-proc one: `out` must be usable even while `ins` forces the slot alive. }
procedure Mixed;
var i, ins, outv, a, b: LongInt;
begin
  ins := 0; outv := 0; a := -1; b := -1;
  for i := 1 to 300 do
  begin
    outv := outv + 2;
    try
      ins := ins + 3;
      if i = 211 then Boom;
    except
      a := ins;
      b := outv;
    end;
  end;
  Writeln('MIX i=', i, ' ins=', ins, ' out=', outv, ' a=', a, ' b=', b);
end;

{ Nested: the inner handler's store is inside the OUTER protected region, so
  a span rule that stops at the inner try must still cover it. }
procedure Nested;
var i, x, y: LongInt;
begin
  x := 0; y := -1;
  for i := 1 to 120 do
  begin
    try
      try
        x := x + 1;
        if i = 77 then Boom;
      except
        x := x + 1000;      { runs after the inner longjmp, inside the outer try }
        if i = 77 then Boom;
      end;
    except
      y := x;
    end;
  end;
  Writeln('NEST i=', i, ' x=', x, ' y=', y);
end;

{ try/finally lowers the finally body TWICE -- once on the normal path (after
  IR_EXC_LEAVE but before the handler label) and once on the exception path.
  A span that ends at the handler label covers the first copy; one that ended
  at IR_EXC_LEAVE would cover neither, and the second copy is where the
  rollback has already happened. }
procedure Fin;
var i, x, n: LongInt;
begin
  x := 0; n := 0;
  for i := 1 to 90 do
  begin
    try
      try
        x := x + 1;
        if i = 55 then Boom;
      finally
        n := n + 1;         { duplicated: normal path AND exception path }
      end;
    except
      x := x + 10000;
    end;
  end;
  Writeln('FIN i=', i, ' x=', x, ' n=', n);
end;

{ The resident is a value PARAM, which -O2 may already hold in r14/r15 before
  -O3 ever runs. Same rollback, different pool. }
procedure ParamResident(p: LongInt);
var i, seen: LongInt;
begin
  seen := -1;
  for i := 1 to 150 do
  begin
    p := p + 1;
    try
      if i = 99 then Boom;
    except
      seen := p;
    end;
  end;
  Writeln('PAR i=', i, ' p=', p, ' seen=', seen);
end;

{ A raise that crosses a call boundary: the callee's epilogue never runs, so
  its callee-saved restores are skipped and only the jmp_buf puts them back. }
function Depth3(n: LongInt): LongInt;
begin
  if n = 0 then Boom;
  Depth3 := Depth3(n - 1) + 1;
end;

procedure Through;
var i, acc, seen: LongInt;
begin
  acc := 0; seen := -1;
  for i := 1 to 60 do
  begin
    acc := acc + i;
    try
      if i = 41 then gSink := Depth3(5);
    except
      seen := acc;
    end;
  end;
  Writeln('THR i=', i, ' acc=', acc, ' seen=', seen);
end;

begin
  OutsideOnly;
  InsideOnly;
  Mixed;
  Nested;
  Fin;
  ParamResident(1000);
  Through;
end.
