{ When does a character-ish thing become a `PChar`?

  pxx answered that in three unrelated places and got three different answers,
  two of which segfaulted. All three rows below are measured against fpc 3.2.2
  and the rule is FPC's, not one invented here:

    a character CONSTANT converts to a pointer to a NUL-terminated one-character
    string; a character VARIABLE does not convert at all.

  1. ARGUMENT CONVERSION. `Show('-')`, `Show(#45)` and `Show(Dash)` were already
     right; `Show(Chr(45))` passed the ORDINAL and SEGFAULTED, because the
     conversion keys on the argument being a literal NODE and `Chr(45)` was an
     un-folded call. Folding it makes it the constant it is. The two shapes FPC
     refuses — a `Char` variable, and `Chr(i)` for a variable i — are now
     refused here too, with a message that says which of the two rules applies;
     they used to compile and dereference address 45.

  2. PARAMETER DEFAULTS. `procedure D(p: PChar = '-')` was a declaration-time
     error, at BOTH lengths — nothing about it depended on the literal being one
     character, which is what separated it from the family above. And there are
     two mechanisms that fill an omitted argument: the parser fills `D;`, the IR
     fills `D()` and the tail of `E(1)`. Both are exercised below, deliberately
     and redundantly, because the first fix touched only one of them and the
     obvious repro (`D;`) could not tell.

  3. EXPRESSION RESULT TYPE. `Writeln('diff=', b - a)` for two PChars used to
     print `diff=` and segfault: the subtraction was right and the static type
     of the un-assigned result stayed PChar, so Writeln picked its
     NUL-terminated-string overload. Already fixed elsewhere by the time this
     umbrella was taken; kept as a regression row, since nothing else pins it.

  bug-p-three-mechanisms-decide-what-becomes-a-pchar-and-they-disagree }
program test_char_to_pchar_conversion;

const
  Dash = '-';
  K    = 45;

type
  TC = class
    procedure M(p: PChar = 'meth'); virtual;
  end;

procedure Show(p: PChar);
begin
  WriteLn('arg   : ', p);
end;

procedure D(p: PChar = '-');
begin
  WriteLn('dflt  : ', p);
end;

procedure E(n: Integer; p: PChar = '--');
begin
  WriteLn('tail  : ', n, ' ', p);
end;

function F(p: PChar = 'fn'): Integer;
begin
  WriteLn('fnret : ', p);
  F := 1;
end;

procedure TC.M(p: PChar = 'meth');
begin
  WriteLn('meth  : ', p);
end;

var
  buf: array[0..15] of Char;
  pa, pb: PChar;
  o: TC;
  r: Integer;
begin
  { 1 — every character CONSTANT spelling, including the two that are not
    literals in the source text }
  Show('-'); Show('--'); Show(#45); Show(Dash); Show(Chr(45)); Show(Chr(K));
  WriteLn('ord   : ', Ord(Chr(45)), ' ', Ord('A'), ' ', Ord(Dash));

  { 2 — both fill mechanisms: `D;` is the parser's, `D()` and `E(1)` the IR's }
  D; D(); D('z');
  E(1); E(2, 'y');
  r := F; r := F('q');
  o := TC.Create;
  o.M; o.M('x');

  { 3 — PChar - PChar is a ptrdiff in EVERY position, not only when assigned }
  pa := @buf[0];
  pb := @buf[2];
  r := pb - pa;
  WriteLn('diff  : ', r, ' ', pb - pa);
end.
