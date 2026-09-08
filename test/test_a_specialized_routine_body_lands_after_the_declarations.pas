program test_a_specialized_routine_body_lands_after_the_declarations;
{ A generic routine's concrete body was spliced at the TEMPLATE's own
  declaration position, so the substituted type argument had to be declared
  ABOVE the template. FPC has no such rule.
  bug-p-an-imported-generic-routine-is-spliced-before-the-programs-own-type-section

  FOUR ROWS, AND TWO OF THEM ARE THE CONTROLS THAT HID IT. The ticket said the
  local case "has never had this bug"; it has, and row 2 is the measurement —
  a template declared ABOVE the type it is specialized on fails in a single
  file, with no unit and no import. Rows 1 and 3 are the shapes that happened
  to work, and they are why the defect read as an import problem:

    1  local-below   template BELOW its type argument     (worked before)
    2  local-above   template ABOVE its type argument     <- also broken
    3  unit-unittype imported template, UNIT's type       (worked before)
    4  unit-progtype imported template, PROGRAM's type    <- the reported bug

  Each row returns a DIFFERENT tag, so a row cannot pass by picking up another
  row's specialization: 11, 22, 33, 44, none of them a zero, a default or
  SizeOf(Integer). The two spellings that share a template (rows 3 and 4) would
  print each other's number if the mangled names collided. }
{$mode objfpc}
uses ugenfuncsplice;

{ row 1: the type is declared first, then the template — the shape that worked }
type TBelow = record Tag: LongInt; end;

generic function TagBelow<T>(const a: T): LongInt;
begin Result := a.Tag; end;

{ row 2: the template first, then the type — the same file, and it did not }
generic function TagAbove<T>(const a: T): LongInt;
begin Result := a.Tag; end;

type TAbove = record Tag: LongInt; end;

{ row 4: a type of the PROGRAM's, for the imported template }
type TInProg = record Tag: LongInt; end;

var
  b: TBelow;
  a: TAbove;
  u: TInUnit;
  p: TInProg;
begin
  b.Tag := 11; a.Tag := 22; u.Tag := 33; p.Tag := 44;
  Writeln('local-below   ', specialize TagBelow<TBelow>(b));
  Writeln('local-above   ', specialize TagAbove<TAbove>(a));
  Writeln('unit-unittype ', specialize TagOf<TInUnit>(u));
  Writeln('unit-progtype ', specialize TagOf<TInProg>(p));
end.
