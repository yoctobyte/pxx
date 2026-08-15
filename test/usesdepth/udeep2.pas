unit udeep2;
{ Middle. Names udeep3 in its INTERFACE — which is NOT a re-export: udeep1 and
  the program below it must not see udeep3's names through this clause. What
  they may see is what udeep2 itself exports. }
interface
uses udeep3;
function Middle: Integer;
implementation
var r: TDeepRec; e: TDeepEnum; a: TDeepArr; x: TDeepAlias;
function Middle: Integer;
begin
  r.a := DeepInt; e := deB; a[0] := DeepVar; x := 1;
  Middle := r.a + Ord(e) + a[0] + Integer(x) + DeepFunc + Length(DeepStr);
  { DeepChar is COMPARED rather than Ord()'d. It has to be named to prove the
    char-const table honours the rule, but Ord() on a one-character untyped
    const answers its ADDRESS instead of its code point in pxx (pre-existing,
    reproduces on `pinned` too — bug-pascal-ord-of-a-one-char-string-const-is-its-address).
    This canary is about namespace scope; it must not go red for that. }
  if DeepChar = 'z' then Middle := Middle + 122;
end;
end.
