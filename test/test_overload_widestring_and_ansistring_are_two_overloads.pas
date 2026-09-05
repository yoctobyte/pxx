{$define PXX_WIDE_PAYLOAD}
program test_overload_widestring_and_ansistring_are_two_overloads;
{ A managed string is ONE TTypeKind (tyAnsiString) carrying an element WIDTH, so
  at kind level `AnsiString` and `WideString` exactly matched each other and
  every candidate: FindProcOverloadRec called the second declaration a duplicate
  of the first, wrote its body into the first one's row, and every call to
  EITHER ran whichever was declared LAST. The FPC conformance row tover1 is that
  bug end to end -- it compiles, runs, and prints "Failure!".

  THE {$define} IS LOAD-BEARING AND IS NOT A TEST FLAG. Without it `widestring`
  is a plain ALIAS of `ansistring` (pasparser_decl.inc's alias-break arm, gated
  on exactly this define), so the two declarations below really would be one
  type declared twice -- which FPC rejects too, and which no signature rule
  should accept. The width can only be part of a signature where the width can
  differ at all, so this is the only build in which the fix is reachable.
  test_widestring_alias_gate.pas pins the other direction.

  ShortString is here as the control that the split did not disturb the kind
  that was ALREADY distinct, and the reversed pair is here because with the fix
  absent the answer is "whichever was last" -- one order alone passes half its
  rows by luck.

  Fails on pin v403 (214500da2), which prints `ansi 2` for the wide row and
  warns "duplicate definition of 'f'". }

function f(s: shortstring): Integer; overload; begin f := 1; end;
function f(s: ansistring): Integer;  overload; begin f := 2; end;
function f(s: widestring): Integer;  overload; begin f := 3; end;

function g(s: widestring): Integer;  overload; begin g := 3; end;
function g(s: ansistring): Integer;  overload; begin g := 2; end;

var ss: shortstring; a: ansistring; w: widestring;
begin
  ss := ''; a := ''; w := '';
  WriteLn('short ', f(ss));
  WriteLn('ansi  ', f(a));
  WriteLn('wide  ', f(w));
  WriteLn('rev a ', g(a));
  WriteLn('rev w ', g(w));
end.
