program test_promoint_function_result;
{ Regression: a function RETURNING PromoInt must return through a caller-owned
  hidden destination, like a record or a Variant.

  A promo value is a {tag, payload} STRUCT and its rvalue is the SLOT ADDRESS,
  but RetViaHiddenDest did not list the promo kinds — so the callee handed back
  the address of its own DYING Result local and the caller read freed stack.
  `function mk: PromoInt; begin end;` + `writeln(mk)` segfaulted with an EMPTY
  body, which is what shows it was never about the assignment.
  bug-a-promoint-function-result-crashes }
function mk: PromoInt;
begin Result := 12; end;

function big: PromoInt;         { forces the HEAP tier, not just the inline one }
var i: Integer;
begin
  Result := 1;
  for i := 1 to 40 do Result := Result * 10;
end;

function viaOp(n: PromoInt): PromoInt;   { promo param AND promo result }
begin Result := n + 0; end;

function twice(n: PromoInt): PromoInt;
begin Result := n * 2; end;

var p, q: PromoInt; i: Integer;
begin
  writeln(mk);                  { 12 }
  writeln(big);                 { 10^40 — verified against Python }
  p := mk;  writeln(viaOp(p));  { 12 }
  writeln(twice(p));            { 24 }
  q := big; writeln(viaOp(q));  { 10^40, through the heap tier }
  writeln(p + 1);               { 13 — the result survives as an operand }
  for i := 1 to 500 do p := twice(p);   { repeated: a UAF or leak shows here }
  writeln(Ord(p > 0));          { 1 }
  writeln('OK');
end.
