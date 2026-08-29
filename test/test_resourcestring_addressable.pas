program test_resourcestring_addressable;

// A `resourcestring` is a runtime-replaceable VARIABLE in FPC, not a literal
// alias, which is why its address can be taken. The corpus shape that needs it
// is Delphi's `Exception.CreateRes(@SArgumentOutOfRange)` -- 28 sites in
// rtl-generics -- where the parameter is PResStringRec = ^string.
//
// NOTE: no brace-comments anywhere in this file. A '}' inside a { } comment
// ends the comment early in FPC and silently disables the oracle.
// bug-p-a-resourcestring-is-not-addressable

uses SysUtils;

resourcestring
  SPlain   = 'out of range';
  SComma   = ',';                 // one char: still a STRING, not a Char const
  SJoined  = 'ab' + 'cd';         // the concatenation form

type
  PResStr = ^string;

function Deref(p: PResStr): string;
begin
  if p = nil then Deref := '<nil>' else Deref := p^;
end;

var
  p: PResStr;
begin
  // read it like any string
  WriteLn('plain ', SPlain);

  // take its address and dereference -- the whole point of the ticket
  p := @SPlain;
  WriteLn('deref ', p^);

  // through a parameter, which is the CreateRes shape
  WriteLn('param ', Deref(@SPlain));

  // a ONE-CHARACTER resourcestring is a string with an address, not a Char
  WriteLn('comma ', Deref(@SComma));
  WriteLn('clen ', Length(SComma));

  // the concatenation form gets storage too
  WriteLn('join ', Deref(@SJoined));

  // runtime-replaceable THROUGH THE POINTER. Note FPC refuses a direct
  // `SPlain := 'x'` (Variable identifier expected) -- pxx accepts it, which is
  // the 'we accept a form FPC rejects' row of CLAUDE.md's compat table, not a
  // defect. Kept out of this file so the oracle stays usable.
  p^ := 'replaced';
  WriteLn('after ', Deref(@SPlain));
end.
