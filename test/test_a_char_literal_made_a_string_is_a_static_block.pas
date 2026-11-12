program test_a_char_literal_made_a_string_is_a_static_block;
{ A one-char literal made into an AnsiString -- `s := 'x'`, or 'x' passed to a
  string parameter -- takes the literal pool's static block at -O2 instead of a
  fresh heap block per evaluation (EmitStaticCharHandle). What must not change:
  writing into the string afterwards copies first, so the NEXT evaluation of the
  same literal still reads 'x'; #0 and #255 keep their length and code; and a
  callee that writes into or rebinds its by-value copy leaves the literal alone.
  The loop at the end is the census half: a static block is never freed, and a
  copy-on-write of it must be. }
{$mode objfpc}{$H+}
type TQ = class procedure M(s: AnsiString); end;
var s, u: AnsiString; i, n: Integer; o: TQ; pm: procedure(a: AnsiString);
procedure P(a: AnsiString); begin a := a + '!'; Write(a, ' '); end;
procedure PQ(a: AnsiString); begin a := a + '!'; n := n + Length(a); end;
procedure Q(x: Integer; a: AnsiString; y: Integer); begin Write(x, a, y, ' '); end;
procedure TQ.M(s: AnsiString); begin s[1] := 'Z'; Write(s, ' '); end;
begin
  for i := 1 to 3 do
  begin
    s := 'x';
    Write(s, Length(s), ' ');
    s[1] := 'y';
    Write(s, ' ');
    u := s; u := u + 'q'; Write(u, ' ');
  end;
  WriteLn;
  s := #0; WriteLn(Length(s), ' ', Ord(s[1]));
  s := #255; WriteLn(Length(s), ' ', Ord(s[1]));
  P('c'); P('c'); Q(1, 'd', 2); Q(1, 'd', 2);
  o := TQ.Create; o.M('m'); o.M('m');
  pm := @P; pm('e'); pm('e');
  WriteLn;
  s := 'k'; u := s; s[1] := 'w'; WriteLn(s, u);
  n := 0;
  for i := 1 to 20000 do
  begin
    s := 'x'; s[1] := 'y'; u := s; u := u + 'q';
    PQ('c');
    s := 'k'; u := s; s[1] := 'w';
    n := n + Length(u);
  end;
  o.Free;
  WriteLn(n, ' ', s, u);
end.
