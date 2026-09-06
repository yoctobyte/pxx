program test_an_overload_candidate_spells_an_array_parameter_as_an_array_fail;
{ MUST NOT COMPILE. The refusal is the point; so is its WORDING.

  `Procs[].Params[j].TypeKind` is one field with two meanings -- the parameter's
  OWN kind when IsArray is False, its ELEMENT kind when IsArray is True -- and
  the overload-candidate report read it as the first, unconditionally. So

      procedure OnlyArr(const a: array of LongInt);   OnlyArr(3);

  was refused with `candidates: OnlyArr(LongInt)`: the message says "this does
  not match" and then displays something that looks exactly like the call the
  programmer just made. A diagnostic that argues for the mistake is worse than
  a terse one.

  The rows below cover the three spellings that reach IsArray -- an open array,
  a NAMED dynamic array, and a 2-deep named dynamic array -- because the depth
  comes from ProcParamDynDepth and 1 is also its floor, so a one-deep row alone
  cannot tell "used the depth" from "printed the prefix once".

  The control is `Mixed`, and it is a control precisely because its two
  overloads land in ONE candidate list from ONE refused call: the array arm
  must gain the prefix and the plain arm must not. Two earlier spellings of
  this control could not fail. `Plain(1)` compiles, so `Plain` never reached a
  candidate list at all. `Plain('x')` ALSO compiles -- an AnsiString argument
  to a LongInt parameter is accepted here, which is its own question and not
  this file's -- so it never reached one either. A control has to be inside the
  population it controls, and "it is refused" was an assumption both times.

  refactor-p-a-parameters-own-kind-and-its-element-kind-are-one-field-and-the-name-says-neither }
{$mode objfpc}{$H+}
type
  TDyn  = array of LongInt;
  TDyn2 = array of array of LongInt;
procedure OnlyArr(const a: array of LongInt); begin WriteLn(Length(a)); end;
procedure OnlyNamed(const a: TDyn);  begin WriteLn(Length(a)); end;
procedure OnlyNamed2(const a: TDyn2); begin WriteLn(Length(a)); end;
procedure Mixed(const a: array of LongInt); overload; begin WriteLn(Length(a)); end;
procedure Mixed(a: LongInt; b: LongInt); overload; begin WriteLn(a + b); end;
begin
  Mixed(nil, nil, nil);
  OnlyArr(3);
  OnlyNamed(3);
  OnlyNamed2(3);
end.
