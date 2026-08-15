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
  { Ord(DeepChar) restored 2026-08-15: a one-character untyped const is now
    typed as a Char, as FPC types it, so Ord() answers its code point instead
    of the string value's ADDRESS
    (bug-pascal-ord-of-a-one-char-string-const-is-its-address). The total is
    unchanged — the comparison form it replaces added the same 122 — so this
    canary's expected value does not move. }
  Middle := r.a + Ord(e) + a[0] + Integer(x) + DeepFunc + Length(DeepStr)
            + Ord(DeepChar);
end;
end.
