program test_a_unit_qualified_read_of_a_same_named_global;
{ A UNIT-QUALIFIED name is not a bare own name, whatever it is spelled like.

  `uqualres.BOAT` read inside `function boat` matched the bare-own-name arm of
  the expression parser on the NAME alone -- the arm that implements FPC's
  `FuncName` synonym for `Result` -- and was compiled as boat's own result
  variable. It answered 0 (the uninitialised result) where FPC answers 115, and
  the function with the identical body under a different name answered 115. The
  qualifier had already been consumed into qUnit; every sibling arm in that
  routine that must not claim a qualified name tests it and this one did not.

  --warn-self-result fires here and says `bare own name`, which is the
  diagnostic being right about the mechanism and wrong about the word, so the
  warning could not be read as the bug either.

  Each pair is one collision and its control: the SAME read from a function
  named something else. A row that only checked the colliding spelling could not
  tell a fixed read from a lucky one.
  bug-a-a-unit-qualified-read-of-a-same-named-global-is-hijacked-by-the-result-variable }
uses uqualres;

{ Case-INSENSITIVELY equal to the global it reads, which is the spelling the
  NilPy twin of this bug wore (`lines.MOTORKRUISER` inside `def motorkruiser`):
  Pascal folds case, so `boat` and `BOAT` are one name and the arm matched
  through its CaseEqual test rather than through the exact one. A second reader
  spelled `BOAT` would be a DUPLICATE of this function rather than a new row --
  the compiler says so -- so the two spellings cannot both appear here. }
function boat: Integer;
begin
  boat := uqualres.BOAT;
end;

function control_boat: Integer;
begin
  control_boat := uqualres.BOAT;
end;

{ A FUNCTION in the unit, same name as the reader, reached through the qualifier:
  the arm excludes a following '(' as a recursive call, so this is the shape that
  reaches it WITH a qualifier and without parentheses being the discriminator. }
function Hull: Integer;
begin
  Hull := uqualres.Hull();
end;

{ With PARAMETERS, where the arm is not gated on the paramless diagnostic at all
  -- a bare own-name read with parameters is unambiguously the result var, so this
  is the arm at its widest. }
function Other(n: Integer): Integer;
begin
  Other := uqualres.Other + n;
end;

{ A STRING result. Added on the prediction that it would be the GUARANTEED
  control -- an uninitialised managed result is deterministically empty where an
  uninitialised Integer is undefined -- and the prediction was WRONG, so it is
  recorded rather than quietly dropped: measured on the pre-fix compiler
  4e4eda234f6c this row printed `teak`, correctly, and did not warn, so the arm
  never claimed it. It stays as a row because it is correct and because the next
  reader would otherwise make the same prediction.

  WHAT THE CONTROL ACTUALLY IS, measured on that same binary: 115 / 115 / 11 /
  4297021 / teak. Only `Other(5)` reds. The `boat` row IS hijacked -- the
  compiler warns on it -- and still printed the right answer, because
  `boat := uqualres.BOAT` degrades to the self-assignment `boat := boat`, which
  is eliminated, and what is left in the result happens to be the value the
  eliminated load had put there. A parameterised reader cannot hide that way: the
  `+ n` forces the garbage into the arithmetic. So the row that proves the fix is
  the one with a parameter, and the paramless rows are corroboration -- which is
  the whole shape of this bug, a wrong read that usually looks right. }
function DeckName: string;
begin
  DeckName := uqualres.DeckName;
end;

begin
  WriteLn(boat);
  WriteLn(control_boat);
  WriteLn(Hull);
  WriteLn(Other(5));
  WriteLn(DeckName);
end.
