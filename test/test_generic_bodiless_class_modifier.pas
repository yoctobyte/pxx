{ A GENERIC class declared bodyless WITH a Delphi modifier -- `class abstract;`,
  `class sealed(TBase);` -- was mis-parsed, and the damage was reported on an
  EARLIER line that was perfectly fine.

  ParseGenericTemplateNamed detects the bodyless forms up front, because a
  bodyless declaration has no `end` for the depth loop to count down to. Its
  test looked at the token right after `class` for a `(` or a `;` and never
  skipped the `abstract` / `sealed` modifiers that may sit between. So it saw
  `abstract`, concluded the declaration HAS a body, and handed it to the depth
  loop -- which then swallowed every following declaration until it found an
  `end` belonging to something else.

  Three things are all required, which is why it survived: the type must be
  GENERIC (the non-generic path consumes the modifiers itself, in
  pasparser_decl.inc, and was always correct), it must carry a MODIFIER, and it
  must be BODYLESS. `TFwd<T> = class;` -- bodyless, no modifier -- compiled fine
  throughout and is kept below as the control that isolates the modifier as the
  variable.

  Measured before/after, one form per program:

    TAbs<T>     = class abstract;                FAILS before / ok after
    TDerived<T> = class abstract(TBase<T>);      FAILS before / ok after
    TSealedB<T> = class sealed(TBase<T>);        FAILS before / ok after
    TFwd<T>     = class;                         ok before    / ok after

  That last row is the control and it is measured, but it is NOT in the program
  below: FPC rejects `TFwd<T> = class;` with "Type TFwd$1 is not completely
  defined", so including it would cost the oracle. pxx accepting it is the
  ordinary accept-more divergence, not a defect -- it is recorded here rather
  than turned into a ticket.

  The corpus instance is rtl-generics' line 144,
  `TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>);`, whose
  error was reported 24 lines earlier at line 120 on `function DoGetCurrent: T`
  -- a line with nothing wrong with it. Every reduction aimed at the reported
  line failed to reproduce, because the reported line was not the defect.

  Oracle: FPC prints the same line. }
program test_generic_bodiless_class_modifier;

{$MODE DELPHI}

type
  TBase<T> = class
    F: T;
    function Get: T;
  end;

  { the three shapes that were broken }
  TAbs<T> = class abstract;
  TDerived<T> = class abstract(TBase<T>);
  TSealedB<T> = class sealed(TBase<T>);

  { control: a modifier WITH a body. (The other control -- bodyless without a
    modifier -- is measured in the table above but omitted here; see the header.) }
  TBody<T> = class abstract
    G: T;
  end;

  { concrete descendants, so nothing below instantiates an abstract class }
  TConc<T> = class(TBody<T>)
  end;

function TBase<T>.Get: T;
begin
  Result := F;
end;

{ TAbs and TDerived are DECLARED and never instantiated on purpose: the defect
  is in capturing the template, so the declaration alone is the trigger -- that
  is the form the per-form measurement above used. }
var
  b: TBase<Integer>;
  s: TSealedB<Integer>;
  y: TConc<Integer>;
begin
  b := TBase<Integer>.Create;    b.F := 7;
  s := TSealedB<Integer>.Create; s.F := 3;
  y := TConc<Integer>.Create;    y.G := 1;
  writeln('bodiless ', b.Get, ' ', s.Get, ' ', y.G);
end.
