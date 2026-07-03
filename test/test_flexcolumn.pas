program test_flexcolumn;

{ `flexcolumn` calling-convention directive: call arguments to a routine
  declared `flexcolumn` accept write-style `:width[:decimals]` modifiers.
  Each value argument expands to three actuals (value, width, decimals),
  defaulting to 0 / -1 when a modifier is absent, so the routine declares
  (v; w, d) triples. }

procedure ShowInt(x: Int64; w: Int64; d: Int64); flexcolumn;
begin
  writeln('x=', x, ' w=', w, ' d=', d);
end;

{ Two columns: two (value, w, d) triples. }
procedure ShowPair(a: Int64; aw: Int64; ad: Int64; b: Int64; bw: Int64; bd: Int64); flexcolumn;
begin
  writeln('a=', a, ':', aw, ':', ad, ' b=', b, ':', bw, ':', bd);
end;

{ A real formatter: right-pad an integer into a column of width w. }
procedure PadInt(x: Int64; w: Int64; d: Int64); flexcolumn;
var
  s: AnsiString;
  n: Int64;
begin
  Str(x, s);
  n := Length(s);
  while n < w do
  begin
    write(' ');
    n := n + 1;
  end;
  writeln(s);
end;

{ A function with the directive works too. }
function FmtSum(x: Int64; w: Int64; d: Int64): Int64; flexcolumn;
begin
  FmtSum := x + w + d;
end;

var
  wv, dv: Int64;
begin
  ShowInt(42);          { defaults: w=0 d=-1 }
  ShowInt(42:5);        { w=5 d=-1 }
  ShowInt(42:5:2);      { w=5 d=2 }

  { width/decimals are full expressions, not just literals }
  wv := 7; dv := 3;
  ShowInt(42:wv+1:dv);  { w=8 d=3 }

  ShowPair(1:2:3, 4:5); { per-arg modifiers on multiple columns }
  ShowPair(1, 2:9);     { bare first column, modified second }

  PadInt(7:6);
  PadInt(12345:6);

  writeln(FmtSum(10:20:30));  { 60 }

  writeln('OK');
end.
