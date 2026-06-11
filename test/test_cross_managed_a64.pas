program test_cross_managed_a64;
{ AArch64 managed-runtime coverage (compile with -dPXX_MANAGED_STRING): strings,
  records, and dynamic arrays. Mirrors the i386/arm32 cross tests but roots every
  concatenation in an AnsiString operand (pure literal+literal tyString concat is
  the one aarch64 case still deferred). Oracle-matched to x86-64. }

type TPerson = record name: AnsiString; age: Integer; end;

function Greet(name: AnsiString): AnsiString;
begin
  Greet := 'Hi, ' + name;
end;

var
  a, b, c: AnsiString;
  p, q: TPerson;
  ints: array of Integer;
  strs: array of AnsiString;
  i, sum: Integer;
begin
  { strings: assign / concat / retain+COW / param+result / compare / write }
  a := 'foo';
  b := 'bar';
  c := a + b;
  writeln(c);                    { foobar }
  c := a;
  a := 'changed';
  writeln(c);                    { foo }
  writeln(Greet(b));             { Hi, bar }
  if c = 'foo' then writeln('eq') else writeln('ne');   { eq }
  if c = b then writeln('eq') else writeln('ne');       { ne }

  { managed record copy with field independence }
  p.name := 'Alice'; p.age := 30;
  q := p;
  p.name := 'Bob';
  writeln(q.name, ' ', q.age);   { Alice 30 }
  writeln(p.name);               { Bob }

  { dynamic arrays: scalar grow/shrink + AnsiString elements }
  SetLength(ints, 3);
  ints[0] := 10; ints[1] := 20; ints[2] := 30;
  SetLength(ints, 5);
  ints[3] := 40; ints[4] := 50;
  sum := 0;
  for i := 0 to Length(ints) - 1 do sum := sum + ints[i];
  writeln('sum=', sum, ' len=', Length(ints));          { sum=150 len=5 }
  SetLength(ints, 2);
  writeln(ints[0], ' ', ints[1], ' len=', Length(ints)); { 10 20 len=2 }

  SetLength(strs, 2);
  strs[0] := 'foo';
  strs[1] := b + 'baz';          { ansistring-rooted concat -> barbaz }
  writeln(strs[0], ' ', strs[1], ' len=', Length(strs)); { foo barbaz len=2 }
  SetLength(strs, 0);
  writeln('len=', Length(strs));                         { len=0 }
end.
