{$define PXX_WIDE_PAYLOAD}
program test_overload_method_element_aware;
{ The METHOD half of "a parameter's ELEMENT is part of its signature", and it
  needed THREE fixes where the free-routine half needed two — which is why it is
  its own file rather than more rows in the free-routine ones.

  1. REGISTRATION, declaration side. ParseTypeSection recorded no pointee and no
     managed-string width for a method row at all, so `m(p: PChar)` and
     `m(p: PWideChar)` were ONE decl row, both out-of-line bodies bound to it,
     and the second won. The free-routine registration rule could not help: it
     compares against a column nothing had written.
  2. SELECTION. The two method rankers score with OverloadArgRank, which sees
     only the two kinds — so once the candidates really were distinct they tied
     at rank 0 and declaration order decided. Both now break the tie on the
     element, ranking a mismatch merely-compatible rather than impossible, so
     the conversion stays available when it is the only candidate.
  3. The CONSTRUCTOR ranker is a separate copy of (2) with its own candidate
     walk, and it did not even keep the argument NODES — only their kinds. It is
     here because a fix to the method ranker alone leaves `TFoo.Create(pw)`
     running the PChar body, and nothing in the method rows would have shown it.

  The {$define} is load-bearing for the two `s` rows only: without it WideString
  IS AnsiString and those two overloads are one type declared twice. The four
  pointer rows need no define — that half is live in a default build.

  Byte-compared against FPC 3.2.2. On pin v403 (214500da2) FOUR of the six rows
  are wrong and it warns "duplicate definition" three times. }

type TFoo = class
  function m(p: pchar): Integer; overload;
  function m(p: pwidechar): Integer; overload;
  function s(a: ansistring): Integer; overload;
  function s(w: widestring): Integer; overload;
  constructor Create(p: pchar); overload;
  constructor Create(p: pwidechar); overload;
  function ctorTag: Integer;
end;

var gTag: Integer;

function TFoo.m(p: pchar): Integer; begin m := 4; end;
function TFoo.m(p: pwidechar): Integer; begin m := 5; end;
function TFoo.s(a: ansistring): Integer; begin s := 2; end;
function TFoo.s(w: widestring): Integer; begin s := 3; end;
constructor TFoo.Create(p: pchar); begin gTag := 40; end;
constructor TFoo.Create(p: pwidechar); begin gTag := 50; end;
function TFoo.ctorTag: Integer; begin ctorTag := gTag; end;

var f: TFoo; pc: pchar; pw: pwidechar; a: ansistring; w: widestring;
begin
  pc := nil; pw := nil; a := ''; w := '';
  f := TFoo.Create(pc);
  WriteLn('m pc ', f.m(pc));
  WriteLn('m pw ', f.m(pw));
  WriteLn('s a  ', f.s(a));
  WriteLn('s w  ', f.s(w));
  WriteLn('ctor pc ', f.ctorTag);
  f := TFoo.Create(pw);
  WriteLn('ctor pw ', f.ctorTag);
end.
