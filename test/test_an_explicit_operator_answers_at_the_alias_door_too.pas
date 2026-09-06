program test_an_explicit_operator_answers_at_the_alias_door_too;
{$mode delphi}
{ `operator Explicit(a: TFoo): Integer` makes `Integer(f)` a conversion CALL
  rather than a reinterpret of the record's bytes. That has to be true of every
  spelling of the target type, and it was true of only one: the BUILTIN-NAME
  door had the arm and the USER-ALIAS door did not, so `type TInt = Integer;
  TInt(f)` answered 4 — the record's raw first field — where `Integer(f)`
  answered 40. fpc 3.2.2 answers 40 for both and is the oracle for this file.

  Its own file rather than a row in
  test_the_alias_cast_door_answers_like_the_builtin_one.pas because this one
  needs the delphi-mode pragma for `class operator`, and adding a dialect
  pragma to an existing test changes how every other row in it parses — a
  confound that costs more than a file. (Spelled out in words on purpose: a
  mode directive written inside a brace comment ENDS that comment at its own
  closing brace under fpc, which turns the rest of the prose into code. pxx
  reads it as comment throughout and compiled the broken file happily, so the
  fpc oracle is what caught it.)

  The rows vary WHICH DOOR RECOGNISES THE TARGET NAME and hold the operand and
  the overload fixed. The no-overload rows are the controls on that same axis:
  a target with no Explicit for it must still reinterpret at BOTH doors, so a
  helper that fired unconditionally would show there rather than passing
  silently.
  refactor-p-five-dispatch-sites-for-one-named-type-cast }
type
  TFoo = record
    v: Integer;
    class operator Explicit(a: TFoo): Integer;
  end;
  TInt  = Integer;    { alias of the type the overload RETURNS }
  TCard = Cardinal;   { alias of a type it does not — control }
class operator TFoo.Explicit(a: TFoo): Integer;
begin Result := a.v * 10; end;
var f: TFoo; i: Integer; c: Cardinal;
begin
  f.v := 4;
  i := Integer(f);   WriteLn('overload builtin ', i);
  i := TInt(f);      WriteLn('overload alias   ', i);
  { no Explicit returns Cardinal, so both doors must fall through to the
    reinterpret and answer the record's first field }
  c := Cardinal(f);  WriteLn('no-overload builtin ', c);
  c := TCard(f);     WriteLn('no-overload alias   ', c);
end.
