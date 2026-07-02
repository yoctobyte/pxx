{ SPDX-License-Identifier: Zlib }
unit calc;

{ Integer expression evaluator: recursive-descent parse-and-evaluate in one pass
  (no AST, so we sidestep the dynamic-array-in-record codegen bug). Our own unit.

  Grammar (lowest to highest precedence):
    expr   := term   (('+' | '-') term)*
    term   := factor (('*' | '/' | '%') factor)*        ('/' = integer div)
    factor := number
            | '(' expr ')'
            | ('-' | '+') factor
            | ident '(' expr (',' expr)* ')'            (function call)

  Functions: gcd(a,b), min(a,b), max(a,b), pow(a,b), abs(a).
  All arithmetic is Int64 and deterministic; division/mod by zero and any syntax
  error set ok := False (result 0). The reader is a class (zero-initialised
  fields) holding source + cursor, like the json unit. }

interface

type
  TCalc = class
    FSrc: AnsiString;
    FPos: Integer;
    FLen: Integer;
    FOk:  Boolean;

    function Peek: Char;
    procedure SkipWS;
    procedure Fail;
    function ParseExpr: Int64;
    function ParseTerm: Int64;
    function ParseFactor: Int64;
    function ParseNumber: Int64;
    function ParseCall(const name: AnsiString): Int64;
  end;

{ Evaluate expr; ok is False on any syntax / domain error (result then 0). }
function Eval(const expr: AnsiString; var ok: Boolean): Int64;

implementation

function IGcd(a, b: Int64): Int64;
var t: Int64;
begin
  if a < 0 then a := -a;
  if b < 0 then b := -b;
  while b <> 0 do
  begin
    t := b;
    b := a mod b;
    a := t;
  end;
  Result := a;
end;

function IPow(base, exp: Int64): Int64;
var r: Int64;
begin
  r := 1;
  while exp > 0 do
  begin
    r := r * base;
    exp := exp - 1;
  end;
  Result := r;
end;

{ ---- TCalc ---- }

procedure TCalc.Fail;
begin
  Self.FOk := False;
end;

function TCalc.Peek: Char;
begin
  if Self.FPos <= Self.FLen then Result := Self.FSrc[Self.FPos]
  else Result := #0;
end;

procedure TCalc.SkipWS;
var c: Char;
begin
  while Self.FPos <= Self.FLen do
  begin
    c := Self.FSrc[Self.FPos];
    if (c = ' ') or (c = #9) then Self.FPos := Self.FPos + 1
    else Break;
  end;
end;

function TCalc.ParseNumber: Int64;
var r: Int64; c: Char;
begin
  r := 0;
  while Self.FPos <= Self.FLen do
  begin
    c := Self.FSrc[Self.FPos];
    if (c >= '0') and (c <= '9') then
    begin
      r := r * 10 + (Ord(c) - Ord('0'));
      Self.FPos := Self.FPos + 1;
    end
    else Break;
  end;
  Result := r;
end;

function TCalc.ParseCall(const name: AnsiString): Int64;
var a, b: Int64;
begin
  Result := 0;
  Self.SkipWS;
  if Self.Peek <> '(' then begin Self.Fail; Exit; end;
  Self.FPos := Self.FPos + 1;
  a := Self.ParseExpr;
  Self.SkipWS;

  if name = 'abs' then
  begin
    if a < 0 then a := -a;
    Result := a;
  end
  else
  begin
    { two-argument functions }
    if Self.Peek <> ',' then begin Self.Fail; Exit; end;
    Self.FPos := Self.FPos + 1;
    b := Self.ParseExpr;
    Self.SkipWS;
    if name = 'gcd' then Result := IGcd(a, b)
    else if name = 'min' then begin if a < b then Result := a else Result := b; end
    else if name = 'max' then begin if a > b then Result := a else Result := b; end
    else if name = 'pow' then Result := IPow(a, b)
    else Self.Fail;
  end;

  if Self.Peek <> ')' then begin Self.Fail; Exit; end;
  Self.FPos := Self.FPos + 1;
end;

function TCalc.ParseFactor: Int64;
var c: Char; name: AnsiString;
begin
  Self.SkipWS;
  c := Self.Peek;
  if c = '(' then
  begin
    Self.FPos := Self.FPos + 1;
    Result := Self.ParseExpr;
    Self.SkipWS;
    if Self.Peek <> ')' then begin Self.Fail; Result := 0; Exit; end;
    Self.FPos := Self.FPos + 1;
  end
  else if c = '-' then
  begin
    Self.FPos := Self.FPos + 1;
    Result := -Self.ParseFactor;
  end
  else if c = '+' then
  begin
    Self.FPos := Self.FPos + 1;
    Result := Self.ParseFactor;
  end
  else if (c >= '0') and (c <= '9') then
    Result := Self.ParseNumber
  else if ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) then
  begin
    name := '';
    while Self.FPos <= Self.FLen do
    begin
      c := Self.FSrc[Self.FPos];
      if ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) then
      begin
        name := name + c;
        Self.FPos := Self.FPos + 1;
      end
      else Break;
    end;
    Result := Self.ParseCall(name);
  end
  else
  begin
    Self.Fail;
    Result := 0;
  end;
end;

function TCalc.ParseTerm: Int64;
var r, rhs: Int64; c: Char;
begin
  r := Self.ParseFactor;
  while True do
  begin
    Self.SkipWS;
    c := Self.Peek;
    if (c = '*') or (c = '/') or (c = '%') then
    begin
      Self.FPos := Self.FPos + 1;
      rhs := Self.ParseFactor;
      if c = '*' then r := r * rhs
      else
      begin
        if rhs = 0 then begin Self.Fail; r := 0; Exit; end;
        if c = '/' then r := r div rhs else r := r mod rhs;
      end;
    end
    else Break;
  end;
  Result := r;
end;

function TCalc.ParseExpr: Int64;
var r, rhs: Int64; c: Char;
begin
  r := Self.ParseTerm;
  while True do
  begin
    Self.SkipWS;
    c := Self.Peek;
    if (c = '+') or (c = '-') then
    begin
      Self.FPos := Self.FPos + 1;
      rhs := Self.ParseTerm;
      if c = '+' then r := r + rhs else r := r - rhs;
    end
    else Break;
  end;
  Result := r;
end;

function Eval(const expr: AnsiString; var ok: Boolean): Int64;
var rd: TCalc; v: Int64;
begin
  rd := TCalc.Create;
  rd.FSrc := expr;
  rd.FLen := Length(expr);
  rd.FPos := 1;
  rd.FOk := True;
  v := rd.ParseExpr;
  rd.SkipWS;
  if rd.FPos <= rd.FLen then rd.FOk := False;   { trailing junk }
  ok := rd.FOk;
  if ok then Result := v else Result := 0;
end;

end.
