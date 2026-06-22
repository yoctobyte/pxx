program VMDemo;
{ Deterministic oracle for the vm unit (Track B).

  Assembles and runs a bundled set of bytecode programs (loop sum, iterative and
  recursive factorial, a called subroutine) and checks their PRINT output exactly.
  Integer-only, so output is byte-identical across targets. Ends 'ALL OK'. }

uses vm, sysutils;

var
  ok: Boolean;

{ Assemble + run src, compare its output to want (newline-separated values). }
procedure RunProg(const name, src, want: AnsiString);
var m: TMachine; got: AnsiString;
begin
  m := TMachine.Create;
  write(name, ': ');
  if not m.Assemble(src) then
  begin
    ok := False;
    writeln('ASM FAIL: ', m.Err);
    Exit;
  end;
  got := m.Run;
  if not m.Ok then
  begin
    ok := False;
    writeln('RUN FAIL: ', m.Err);
    Exit;
  end;
  if got = want then writeln('ok (', want, ')')
  else
  begin
    ok := False;
    writeln('FAIL: got [', got, '] want [', want, ']');
  end;
end;

var
  loopSum, factIter, factRec, subr: AnsiString;
  m2: TMachine;
begin
  ok := True;

  { sum 1..10 = 55; mem[0]=acc, mem[1]=i. One statement per line. }
  loopSum :=
    'push 0'#10'store 0'#10 +          { acc = 0 }
    'push 1'#10'store 1'#10 +          { i = 1 }
    'loop:'#10 +
    'load 1'#10'push 10'#10'gt'#10'jnz done'#10 +   { if i > 10 goto done }
    'load 0'#10'load 1'#10'add'#10'store 0'#10 +    { acc += i }
    'load 1'#10'push 1'#10'add'#10'store 1'#10 +    { i++ }
    'jmp loop'#10 +
    'done:'#10'load 0'#10'print'#10'halt'#10;
  RunProg('loopsum ', loopSum, '55'#10);

  { iterative factorial 5! = 120; mem[0]=res, mem[1]=n }
  factIter :=
    'push 1'#10'store 0'#10 +
    'push 5'#10'store 1'#10 +
    'fl:'#10'load 1'#10'jz fd'#10 +                 { while n <> 0 }
    'load 0'#10'load 1'#10'mul'#10'store 0'#10 +    { res *= n }
    'load 1'#10'push 1'#10'sub'#10'store 1'#10 +    { n-- }
    'jmp fl'#10 +
    'fd:'#10'load 0'#10'print'#10'halt'#10;
  RunProg('factiter', factIter, '120'#10);

  { recursive factorial via call/ret; argument carried on the operand stack }
  factRec :=
    'push 5'#10'call fact'#10'print'#10'halt'#10 +
    'fact:'#10 +
    'dup'#10'push 2'#10'lt'#10'jz frec'#10 +        { n < 2 ? if not, recurse }
    'ret'#10 +                                      { base: return n }
    'frec:'#10 +
    'dup'#10'push 1'#10'sub'#10'call fact'#10'mul'#10'ret'#10;  { n * fact(n-1) }
  RunProg('factrec ', factRec, '120'#10);

  { subroutine called twice: square(x) = x*x -> 36, 81 }
  subr :=
    'push 6'#10'call sq'#10'print'#10 +
    'push 9'#10'call sq'#10'print'#10 +
    'halt'#10 +
    'sq:'#10'dup'#10'mul'#10'ret'#10;
  RunProg('subr    ', subr, '36'#10 + '81'#10);

  { assembler error surfaces }
  m2 := TMachine.Create;
  write('badmnem : ');
  if m2.Assemble('push 1'#10'frobnicate 2'#10'halt'#10) then
  begin ok := False; writeln('FAIL: expected asm error'); end
  else writeln('rejected (', m2.Err, ')');

  writeln;
  if ok then writeln('ALL OK') else writeln('FAILURES');
end.
