program vob;
{$mode objfpc}
{ AN OVERRIDE IMPLEMENTED BEFORE ITS BASE MUST STILL WIN ITS VMT SLOT.

  Parsing a virtual method's BODY records a VMT fixup for its own class and for
  every subclass that INHERITS the slot. The subclass filter used to be plain
  IsSubclassOf, so a base implemented after its override recorded a fixup on top
  of the child's and the last one written won: the override became unreachable,
  including through a direct TDer(o).Say, with no diagnostic. Implementation
  order is not constrained by Pascal and fpc compiles either order the same, so
  this was a silent wrong answer in ordinary non-generic code.

  Every method body here is deliberately implemented DEEPEST-FIRST, base last --
  the order that used to fail. Rows 5-8 repeat the same hierarchy with the
  bodies in the opposite order, so a "fix" that merely swapped which order
  breaks cannot pass this file.

  The three-level rows are the ones a naive filter still gets wrong: for
  A -> B -> C with B overriding and C not, C inherits B's body and not A's, so
  "is C below A" is true and propagating A into C is still incorrect. Every
  class prints a DIFFERENT letter for that reason -- with a shared answer the
  wrong-slot case and the right one would print the same thing. }
type
  TA = class procedure Say; virtual; end;
  TB = class(TA) procedure Say; override; end;
  TC = class(TB) end;                { no override: must inherit B's }
  TD = class(TA) end;                { no override: must inherit A's }

  TE = class procedure Say; virtual; end;
  TF = class(TE) procedure Say; override; end;
  TG = class(TF) end;

{ deepest first, base last -- the order that used to lose the override }
procedure TB.Say; begin write('B'); end;
procedure TA.Say; begin write('A'); end;

{ and the opposite order, so neither can be the one that happens to work }
procedure TE.Say; begin write('E'); end;
procedure TF.Say; begin write('F'); end;

var a: TA; e: TE; d: TB;
begin
  a := TA.Create; a.Say;
  a := TB.Create; a.Say;
  a := TC.Create; a.Say;
  a := TD.Create; a.Say;
  write(' ');
  e := TE.Create; e.Say;
  e := TF.Create; e.Say;
  e := TG.Create; e.Say;
  { a STATICALLY typed derived receiver takes a different resolution path from
    the TA-typed one above, and it was wrong too -- the slot itself held the
    base's address, so no call site could recover. }
  write(' ');
  d := TB.Create; d.Say;
  writeln;
end.
