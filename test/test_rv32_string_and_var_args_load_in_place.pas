program test_rv32_string_and_var_args_load_in_place;
{ riscv32 loads trailing call arguments that are constants or plain locals
  straight into their a-registers instead of pushing and reloading them. Two
  more kinds now qualify:
  - a frame local's AnsiString handle passed to a by-value or const string
    parameter (the handle is passed as loaded, so refcounts must not move);
  - the address of a frame local passed to a var/out parameter (integers,
    records, and a by-value parameter of the caller forwarded as var).
  Each runs after a first argument that calls something, so the earlier words
  come off the stack first; a call that returns a string through a hidden
  destination is included. Strings and arrays, records of strings and
  parameters already held by reference keep the old path and are exercised
  for contrast. Values only, so x86-64 is the oracle; Churn runs every shape
  500 times under the leak census. }
{$mode objfpc}
uses SysUtils;
type
  TPair = record a, b: LongInt; end;
var
  log: AnsiString;

function Tag(const s: AnsiString): AnsiString;
begin
  Result := '<' + s + '>';
end;

procedure Note(const key, val: AnsiString);
begin
  log := log + key + '=' + val + ';';
end;

function Join3(const a: AnsiString; b: AnsiString; const c: AnsiString): AnsiString;
begin
  b := b + '+';                  { by-value: a local copy, the caller's is untouched }
  Result := a + b + c;
end;

function Pick(const q, name: AnsiString): AnsiString;
var k: LongInt;
begin
  k := Pos(name + '=', q);
  if k = 0 then Result := '' else Result := Copy(q, k + Length(name) + 1, 3);
end;

function ParseN(const s: AnsiString; var v: LongInt): Boolean;
var code: LongInt;
begin
  Val(s, v, code);
  Result := code = 0;
end;

procedure Fill(n: LongInt; var p: TPair; out total: LongInt);
begin
  p.a := n; p.b := n * 2;
  total := p.a + p.b;
end;

procedure Swap2(var x, y: LongInt);
var t: LongInt;
begin
  t := x; x := y; y := t;
end;

procedure Forward(v: LongInt);
var w: LongInt;
begin
  w := v * 10;
  Swap2(v, w);                   { a by-value param's own slot passed as var }
  writeln('forward ', v, ' ', w);
end;

function Cnt(const s: AnsiString; var hits: LongInt): LongInt;
begin
  Inc(hits);
  Result := Length(s);
end;

procedure Shapes(k: LongInt);
var s, t, q, r: AnsiString; n, m, total: LongInt; p: TPair; ok: Boolean;
begin
  s := 'k' + IntToStr(k);
  t := s;
  Note(Tag(s), s);                       { call first, local handle last }
  Note(IntToStr(k), t);
  q := 'a=12&n=' + IntToStr(k mod 997) + '&z=9';
  r := Pick(q, 'n');                     { hidden-dest result, local args }
  ok := ParseN(Pick(q, 'n'), n);         { call first, var local last }
  ok := ok and ParseN(r, m);
  if ok and (n = m) then Note('n', IntToStr(n));
  Fill(k + 1, p, total);                 { two var/out locals trailing }
  Note('fill', IntToStr(p.a) + ',' + IntToStr(p.b) + ',' + IntToStr(total));
  r := Join3(Tag(s), s, t);              { by-value string in the middle }
  Note('join', r);
  Note('s', s);                          { unchanged by Join3 }
  m := 0;
  n := Cnt(Tag(r), m) + Cnt(s, m);
  Note('cnt', IntToStr(n) + '/' + IntToStr(m));
end;

procedure Churn;
var k, n: LongInt; s, u: AnsiString;
begin
  for k := 1 to 500 do
  begin
    log := '';
    Shapes(k);
    s := 'c' + IntToStr(k);              { refcount 1, passed by handle }
    u := Join3(s, s, s);
    if u <> s + s + '+' + s then writeln('bad join ', k);
    n := 0;
    if Cnt(s, n) + Cnt(u, n) <> Length(s) + Length(u) then writeln('bad cnt ', k);
  end;
  writeln(log);
end;

var a, b: LongInt;
begin
  log := '';
  Shapes(7);
  writeln(log);
  log := '';
  Shapes(123456);
  writeln(log);
  Forward(5);
  a := 1; b := 2;
  Swap2(a, b);
  writeln(a, ' ', b);
  Churn;
  log := '';
  writeln('done');
end.
