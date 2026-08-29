unit ugdgbase;
{ Delphi-surface generics declared in a UNIT, used from OTHER files.

  The point of the split: Tokens[] is one array shared by every unit and the
  main program is lexed FIRST, so every use of TBox below sits at a token index
  BELOW this declaration. The desugar that turns `TBox<Integer>` into an alias
  used to sweep only forward from here and could not see them.
  bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized

  The templates carry FIELDS and no methods on purpose. A cross-unit
  specialization of a template that HAS methods streams those method bodies
  into the using unit's INTERFACE section, where a method implementation is not
  a declaration -- a separate, pre-existing gap that reproduces on `pinned`
  with a hand-written objfpc `X = specialize T<LongInt>;` and no Delphi surface
  anywhere. Keeping it out of here keeps this test about one thing. }
{$MODE DELPHI}
interface

type
  TBox<T> = class
    Val: Integer;
  end;

  TPair<A, B> = class
    Tag: Integer;
  end;

implementation

end.
