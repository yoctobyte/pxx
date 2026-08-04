{ A PromoInt PARAMETER — bug-a-promoint-parameter-cannot-be-used-at-all.

  A promotable int is an AGGREGATE ({tag, payload}, TypeSize 16 on a 64-bit
  target), so it now travels the way every large record already does: by
  reference, with the CALLER copying into a hidden temp first. That is what
  gives Pascal value semantics over an address-passing ABI — and it is the
  convention this compiler already had; promo had simply never been joined to it.

  Before, the two ends disagreed. The caller passed the slot ADDRESS (a promo
  rvalue IS its slot address) while the callee's `lea n` addressed an unfilled
  16-byte frame cell, so `@n` was a pointer to a pointer and `n + 0` read the
  caller's address as a TAG word and died in the runtime's heap branch. The type
  was one you could compute with but could not write a function against.

  Both a value that fits the INLINE tier and one that has spilled to the HEAP
  tier are covered: only the heap tier has a managed payload, and it is the
  reason the caller's copy must be PXXPromoCopy (which retains) rather than a
  raw 16-byte copy. }
program t;
uses promocore;

function readIt(n: PromoInt): AnsiString;
begin Result := PXXPromoToStr(@n); end;

{ `Pointer(n)` must mean the same thing as `@n`. It worked for a LOCAL, whose
  rvalue already is its slot address, and crashed for a by-ref PARAMETER, whose
  cell holds the address instead — one spelling, two meanings. }
function readPtr(n: PromoInt): AnsiString;
begin Result := PXXPromoToStr(Pointer(n)); end;

function doubleIt(n: PromoInt): AnsiString;
var t: PromoInt;
begin t := n * 2; Result := PXXPromoToStr(@t); end;

{ passing a parameter straight on to another routine }
function chain(n: PromoInt): AnsiString;
begin Result := doubleIt(n); end;

{ ASSIGNING to the parameter must change the callee's copy and NOT the caller's
  variable. The store path used to exclude by-ref symbols outright, which was
  harmless while promo parameters did not work at all and silently DROPPED the
  write once they did. }
function mutate(n: PromoInt): AnsiString;
begin n := n + 1; Result := PXXPromoToStr(@n); end;

{ the motivating case the ticket was opened for: base conversion written in
  ORDINARY Pascal against PromoInt — it needs a promo parameter, `shr`, a
  machine-int cast and mutation of the parameter, all at once }
function toHex(n: PromoInt): AnsiString;
const digits = '0123456789abcdef';
var d: Integer;
begin
  if n = 0 then begin Result := '0'; Exit; end;
  Result := '';
  while n <> 0 do
  begin
    d := Integer(n and 15);
    Result := digits[d + 1] + Result;
    n := n shr 4;
  end;
end;

var v: PromoInt;
begin
  { INLINE tier }
  v := 12;
  writeln(readIt(v), ' ', readPtr(v), ' ', doubleIt(v), ' ', mutate(v));
  writeln(PXXPromoToStr(@v));          { caller UNCHANGED by mutate }

  { HEAP tier — past Int64, so the payload is a managed string }
  v := 1; v := v * 70000000000;
  writeln(readIt(v), ' ', readPtr(v));
  writeln(doubleIt(v), ' ', chain(v), ' ', mutate(v));
  writeln(PXXPromoToStr(@v));          { caller UNCHANGED }

  { the library function, against both tiers, checked against the runtime's own
    base conversion }
  v := 255;
  writeln(toHex(v));
  v := 1; v := v shl 70;
  writeln(toHex(v), ' ', PXXPromoToBase(@v, 16));
  v := 0;
  writeln(toHex(v));
end.
